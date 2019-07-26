local class = require 'middleclass'
--- 导入需要的模块
local modbus = require 'modbus.init'
local mslave = require 'mslave'
local socketchannel = require 'socketchannel'
local serialchannel = require 'serialchannel'
local csv_tpl = require 'csv_tpl'
local conf_helper = require 'app.conf_helper'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("MODBUS_SLAVE_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.static.API_VER = 1

--- 设定变量的默认值
local default_vals = {
	int = 0,
	string = '',
}

--- 创建Modbus寄存器
local function create_var(device, input, addr, fmt)
	local current = device:get_input_prop(input.name, 'value')
	local val = input.vt and default_vals[input.vt] or 0.0

	return self._slave:add_var(addr, fmt, current or val)
end

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	--- 获取数据接口
	self._api = sys:data_api()
	--- 获取日志接口
	self._log = sys:logger()
	self._log:debug(name.." Application initlized")
end

--- 设定变量的当前值
-- @param var: OPCUA变量对象
-- @param value: 变量的当前值
-- @param timestamp: 时间戳
-- @param quality: 质量戳
local function set_var_value(var, value, timestamp, quality)
	return var:set_value(value)
end


--- 创建数据回调对象
-- @param app: 应用实例对象
local function create_handler(app)
	local api = app._api
	local slave = app._slave
	local log = app._log
	local idx = app._idx
	local nodes = app._nodes
	return {
		--- 处理设备对象添加消息
		on_add_device = function(app, sn, props)
			--- 使用设备SN来生成设备对象的ID
			local device = api:get_device(sn)
			local tpl = app:load_tpl(sn)

			local node = nodes[sn] or {
				device = device,
				vars = {}
			}
			local vars = node.vars
			for i, input in ipairs(props.inputs) do
				local var = vars[input.name]
				if not var then
					local t = tpl.inputs[input.name]
					vars[input.name] = create_var(input, device, t.addr, t.fmt)
				end
			end
			nodes[sn] = node
		end,
		--- 处理设备对象删除消息
		on_del_device = function(app, sn)
			local node = nodes[sn]
			if node then
				--- 删除设备对象
				slave:deleteNode(node.devobj.id, true)
				nodes[sn] = nil
			end
		end,
		--- 处理设备对象修改消息
		on_mod_device = function(app, sn, props)
			local node = nodes[sn]
			if not node or not node.vars then
				assert(false) -- TODO: should not be here
			end
			local vars = node.vars
			for i, input in ipairs(props.inputs) do
				local var = vars[input.name]
				if not var then
					vars[input.name] = create_var(idx, node.devobj, input, node.device)
				end
			end
		end,
		--- 处理设备输入项数值变更消息
		on_input = function(app, sn, input, prop, value, timestamp, quality)
			local node = nodes[sn]
			if not node or not node.vars then
				log:error("Unknown sn", sn)
				return
			end
			--- 设定OPCUA变量的当前值
			local var = node.vars[input]
			if var and prop == 'value' then
				set_var_value(var, value, timestamp, quality)
			end
		end,
	}
end

function app:load_tpl(sn)
	-- Load the template file by sn
	local tpl, err = csv_tpl.load_tpl(sn)
	if not tpl then
		self._log:error("loading csv tpl failed", err)
		return nil, err
	end
	--- inputs
	local inputs = {}
	for _, v in ipairs(tpl.inputs) do
		inputs[v.name] = {
			addr = v.addr,
			fmt = v.fmt
		}
	end
	--- outputs
	local outputs = {}
	for _, v in ipairs(tpl.outputs) do
		outputs[v.name] = {
			addr = v.addr,
			fmt = v.fmt
		}
	end

	local commands = {}
	for _, v in ipairs(tpl.commands) do
		commands[v.name] = {
			addr = v.addr,
			fmt = 'json'
		}
	end

	return {
		inputs = inputs,
		outputs = outputs,
		commands = commands
	}
end

--- 应用启动函数
function app:start()
	--- 设定回调处理函数(目前此应用只做数据采集)
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value, timestamp, priv)
			return self:write_output(sn, output, prop, value, timestamp, priv)
		end,
		on_ctrl = function(...)
			print(...)
		end,
	})

	csv_tpl.init(self._sys:app_dir())

	local config = self._conf or {}

	self._handler = create_handler(self)
	self._api:set_handler(self._handler, true)

	--- List all devices and then create registers
	self._sys:fork(function()
		local devs = self._api:list_devices() or {}
		for sn, props in pairs(devs) do
			--- Calling handler for creating opcua object
			self._handler.on_add_device(self, sn, props)
		end
	end)

	local slave = nil

	--- 获取配置
	local conf = helper:config()
	conf.channel_type = conf.channel_type or 'socket'
	if conf.channel_type == 'socket' then
		conf.opt = conf.opt or {
			host = "127.0.0.1",
			port = 1503,
			nodelay = true
		}
	else
		conf.opt = conf.opt or {
			port = "/dev/ttymxc1",
			baudrate = 115200
		}
	end
	if conf.channel_type == 'socket' then
		local apdu = config.apdu and modbus['apdu_'..config.apdu] or modbus.apdu_tcp
		slave = mslave(socketchannel, conf.opt, apdu, 1)
	else
		local apdu = config.apdu and modbus['apdu_'..config.apdu] or modbus.apdu_rtu
		slave = mslave(serialchannel, conf.opt, apdu, 1)
	end

	self._slave = slave

	return true
end

--- 应用退出函数
function app:close(reason)
	if self._slave then
		self._slave:close()
		self._slave = nil
	end
	print(self._name, reason)
end

--- 应用运行入口
function app:run(tms)
	if not self._slave then
		return
	end

	for _, dev in ipairs(self._devs) do
		self:read_dev(dev.dev, dev.stat, dev.unit, dev.tpl)
	end

	--- 返回下一次调用run之前的时间间隔
	return self._conf.loop_gap or 5000
end

--- 返回应用对象
return app
