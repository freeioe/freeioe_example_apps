local class = require 'middleclass'
--- 导入需要的模块
local ubus = require 'ubus'
local focas = require 'focas'
local focas_ubus = require 'focas_ubus'
local csv_tpl = require 'csv_tpl'
local conf_helper = require 'app.conf_helper'
local cjson = require 'cjson'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("FANUC_FOCAS_UBUS_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 2

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

	--self._run_ubusd = true
end

--- 应用启动函数
function app:start()
	--- 设定回调处理函数(目前此应用只做数据采集)
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
			return self:write_output(sn, output, prop, value)
		end,
		on_ctrl = function(...)
			print(...)
		end,
	})

	csv_tpl.init(self._sys:app_dir())
	if self._run_ubusd then
		local ubusd = focas_ubus:new(self._sys:app_dir())
		ubusd:prepare()
		ubusd:start()
		self._ubusd = ubusd
	end

	---获取设备序列号和应用配置
	local sys_id = self._sys:id()

	local config = self._conf or {}
	config.devs = config.devs or {
		{ ip="192.168.0.200", port=8193, name = 'cnc01', sn = 'xxx-xx-1', tpl = 'cnc' },
		--{ ip="127.0.0.2", port=8193, name = 'cnc02', sn = 'xxx-xx-2', tpl = 'cnc' },
	}

	--- 获取云配置
	if not config.devs or config.cnf then
		config = config.cnf .. '.' .. config.ver
	end

	local helper = conf_helper:new(self._sys, config)
	helper:fetch()

	local bus = ubus:new()
	if self._run_ubusd then
		bus:connect()
	else
		bus:connect('/tmp/ubus.sock')
		--bus:connect("172.30.11.232", 11000)
	end

	local r, err = bus:status()
	if not r then
		self._log:error("Connect to UBUS failed!", err)
		return false
	end
	self._ubus = bus

	--- 获取配置
	local conf = helper:config()
	conf.ubus_name = conf.ubus_name or 'focas'
	self._ubus_name = conf.ubus_name

	self._devs = {}
	for _, v in ipairs(helper:devices()) do
		assert(v.sn and v.name and v.ip and v.port and v.tpl)

		--- 生成设备的序列号
		local dev_sn = sys_id.."."..v.sn
		local tpl, err = csv_tpl.load_tpl(v.tpl)
		print(cjson.encode(tpl))
		if not tpl then
			self._log:error("loading csv tpl failed", err)
		else
			local meta = self._api:default_meta()
			meta.name = tpl.meta.name or "Fanuc CNC"
			meta.description = tpl.meta.desc or "Fanuc CND Device"
			meta.series = tpl.meta.series or "XXX"
			meta.inst = v.name
			--- inputs
			local inputs = {}
			for _, v in ipairs(tpl.inputs) do
				inputs[#inputs + 1] = {
					name = v.name,
					desc = v.desc,
					vt = v.vt
				}
			end

			local focas_dev = focas:new(v.ip, v.port, v.name, v.sn, tpl)
			--- Funcs
			for _, v in ipairs(tpl.funcs) do
				v.inputs = focas_dev:inputs(v.func, v.name, v.desc, v.vt, v.rate)
				for _, v in ipairs(v.inputs) do
					inputs[#inputs + 1] = {
						name = v.name,
						desc = v.desc,
						vt = v.vt
					}
				end
			end

			local dev = self._api:add_device(dev_sn, meta, inputs, outputs)

			table.insert(self._devs, {
				sn = dev_sn,
				dev = dev,
				focas = focas_dev,
				tpl = tpl,
			})
		end
	end

	for _, dev in ipairs(self._devs) do
		local r, err = dev.focas:connect(self._ubus, self._ubus_name)
		assert(r, err)
		if not r then
			self._log:error("Connect to device failed!", err)
		end
	end

	return true
end

--- 应用退出函数
function app:close(reason)
	if self._ubusd then
		self_ubusd:stop()
	end
	self._log:notice("app closed", self._name, reason)
end

function app:read_packet(dev, focas, func, params, inputs)
	--- 设定读取的起始地址和读取的长度
	local func = focas:get_func_name(func or 'read_pmc')
	if func == 'read_pmc' then
		return
	end

	local f = focas[func]
	if not f then
		self._log:error("function code incorrect", func)
		return nil, "function code incorrect"
	end

	local data, err = f(focas, table.unpack(params))
	if not data then
		self._log:error('call '..func..' failed', err)
		return nil, err
	end

	local cjson = require 'cjson.safe'
	--print(cjson.encode(data))

	if func ~= 'read_pmc' and #inputs == 1 then
		new_data = {}
		local input = inputs[1]
		if type(data) == 'table' then
			if #data >= 1 then
				new_data[input.vname] = data[1]
			end
		else
			new_data[input.vname] = data
		end

		data = new_data
	end

	for i, input in ipairs(inputs) do
		local key = input.vname or i
		print(data[key], key, input.vt,  input.rate)

		if input.rate and input.rate ~= 1 then
			local val = (data[key] or 0) * input.rate
			dev:set_input_prop(input.name, "value", val)
		else
			if input.vt == 'int' then
				dev:set_input_prop(input.name, "value", math.tointeger(data[key]))
			else
				dev:set_input_prop(input.name, "value", data[key])
			end
		end
	end
end

function app:invalid_dev(dev, pack)
	for _, input in ipairs(pack.inputs) do
		dev:set_input_prop(input.name, "value", 0, nil, 1)
	end
end

function app:read_dev(dev, focas, tpl)
	for _, pack in ipairs(tpl.packets) do
		local params = { pack.addr_type, pack.data_type, pack.start, pack.len }
		self:read_packet(dev, focas, 'read_pmc', params, pack.inputs)
	end
	for _, func in ipairs(tpl.funcs) do
		self:read_packet(dev, focas, func.func, func.params, func.inputs)
	end
end

--- 应用运行入口
function app:run(tms)
	for _, dev in ipairs(self._devs) do
		self:read_dev(dev.dev, dev.focas, dev.tpl)
	end

	--- 返回下一次调用run之前的时间间隔
	return self._conf.loop_gap or 5000
end

--- 返回应用对象
return app
