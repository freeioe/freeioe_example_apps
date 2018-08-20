local class = require 'middleclass'
--- 导入需要的模块
local dlt645_client = require 'dlt645.client'
local dlt645_data = require 'dlt645.data'
local serialchannel = require 'serialchannel'
local csv_tpl = require 'csv_tpl'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("DL/T_645_2007_App")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 1

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如dlt645_1
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

	---获取设备序列号和应用配置
	local sys_id = self._sys:id()
	local config = self._conf or {}

	config.opt = config.opt or {
		port = "/dev/ttymxc1",
		--port = "/tmp/ttyS10",
		baudrate = 9600
	}

	config.devs = config.devs or {
		{ addr = 992233445566, name = 'S1', sn = 'xxx-xx-1', tpl = 's1' },
		{ addr = 990000000001, name = 'S2', sn = 'xxx-xx-2', tpl = 's2' },
	}

	self._devs = {}
	for _, v in ipairs(config.devs) do
		assert(v.sn and v.name and v.addr and v.tpl)

		--- 生成设备的序列号
		local dev_sn = v.sn

		local tpl, err = csv_tpl.load_tpl(v.tpl)
		if not tpl then
			self._log:error("loading csv tpl failed", err)
		else
			local meta = self._api:default_meta()
			meta.name = tpl.meta.name or "DLT645 Meter"
			meta.description = tpl.meta.desc or "DLT645 Meter Device"
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
			--- outputs
			local outputs = {}
			for _, v in ipairs(tpl.outputs) do
				outputs[#outputs + 1] = {
					name = v.name,
					desc = v.desc,
				}
			end
			--- 生成设备对象
			local dev = self._api:add_device(dev_sn, meta, inputs, outputs)
			--- 生成设备通讯口统计对象
			local stat = dev:stat('port')

			table.insert(self._devs, {
				addr = v.addr,
				sn = dev_sn,
				dev = dev,
				tpl = tpl,
				stat = stat,
			})
		end
	end

	--- 获取配置
	local fe_required = self._conf.fe_required == true
	self._client = dlt645_client(serialchannel, config.opt, true, fe_required)

	return true
end

--- 应用退出函数
function app:close(reason)
	print(self._name, reason)
end

function app:write_output(sn, output, prop, value)
	local dev = nil
	for _, v in ipairs(self._devs) do
		if v.sn == sn then
			dev = v
			break
		end
	end
	if not dev then
		return false, "Cannot find device sn "..sn
	end

	local tpl_output = nil
	for _, v in ipairs(dev.tpl.outputs or {}) do
		if v.name == output then
			tpl_output = v
			break
		end
	end
	if not tpl_output then
		return false, "Cannot find output "..sn.."."..output
	end

	if prop ~= 'value' then
		return false, "Cannot write property which is not value"
	end
	
	local r, err = self:write_packet(dev.dev, dev.stat, dev.addr, tpl_output, value)
	if not r then
		local info = "Write output failure!"
		local data = { sn=sn, output=output, prop=prop, value=value, err=err }
		self._dev:fire_event(event.LEVEL_ERROR, event.EVENT_DEV, info, data)
	end
	return r, err
end

function app:write_packet(dev, stat, dev_addr, output, value)
	--- 设定写数据的地址
	local req = {
		func = tonumber(output.func) or 0x06, -- 06指令
		addr = dev_addr, -- 地址
		data = dlt645_data.encode(output.addr, value)
	}
	local timeout = output.timeout or 3000

	local val = math.floor(value * (1/output.rate))
	req.data = table.concat({ ef(val) })
	
	--- 设定通讯口数据回调
	self._client:set_io_cb(function(io, msg)
		--- 输出通讯报文
		dev:dump_comm(io, msg)
		--- 计算统计信息
		if io == 'IN' then
			stat:inc('bytes_in', string.len(msg))
		else
			stat:inc('bytes_out', string.len(msg))
		end
	end)
	--- 写入数据
	local r, pdu, err = pcall(function(req, timeout) 
		--- 统计数据
		stat:inc('packets_out', 1)
		--- 接口调用
		return self._client:request(req, timeout)
	end, req, 1000)

	if not r then 
		pdu = tostring(pdu)
		if string.find(pdu, 'timeout') then
			self._log:debug(pdu, err)
		else
			self._log:warning(pdu, err)
		end
		return nil, pdu
	end

	if not pdu then 
		self._log:warning("write failed: " .. err) 
		return nil, err
	end

	--- 统计数据
	stat:inc('packets_in', 1)

	--- 解析数据
	--[[
	local pdu_data = string.sub(pdu, 4)
	local val_ret = df(pdu_data, 1)
	if val_ret ~= val then
		return nil, "Write failed!"
	end
	]]--

	return true
end

function app:read_packet(dev, stat, dev_addr, pack)
	--- 设定读取的起始地址和读取的长度
	local req = {
		code = 0x11,
		addr = dev_addr,
		data_addr = pack.addr-- 数据标识地址
		-- TODO: For reading count/time
	}

	--- 设定通讯口数据回调
	self._client:set_io_cb(function(io, msg)
		--- 输出通讯报文
		dev:dump_comm(io, msg)
		--- 计算统计信息
		if io == 'IN' then
			stat:inc('bytes_in', string.len(msg))
		else
			stat:inc('bytes_out', string.len(msg))
		end
	end)
	--- 读取数据
	local timeout = pack.timeout or 3000
	local r, pdu, err = pcall(function(req, timeout) 
		--- 统计数据
		stat:inc('packets_out', 1)
		--- 接口调用
		return self._client:request(req, timeout)
	end, req, timeout)

	if not r then 
		pdu = tostring(pdu)
		if string.find(pdu, 'timeout') then
			self._log:debug(pdu, err)
		else
			self._log:warning(pdu, err)
		end
		return self:invalid_dev(dev, pack)
	end

	if not pdu then 
		self._log:warning("read failed: " .. err) 
		return self:invalid_dev(dev, pack)
	end

	--- 统计数据
	self._log:trace("read input registers done!", dev_addr)
	stat:inc('packets_in', 1)

	--- 解析数据
	if pdu.sflag then
		self._log:warning(string.format("read package failed 0x%02X", pdu.code), pdu.sflag)
		return
	end

	local data_addr, data_value = dlt645_data.decode(pdu.data, pack.format)
	if data_addr ~= pack.addr then
		self._log:warning("Got incorrect data_addr", pack.addr, data_addr)
		return
	end

	local function set_input(input, val)
		if input.format and string.len(input.format) > 0 then
			self._log:warning("Cannot specify data format in correct version")
			-- TODO: for user specified format
		end

		if input.rate and input.rate ~= 1 then
			val = val * input.rate
		end
		if input.vt == 'int' then
			dev:set_input_prop(input.name, "value", math.tointeger(val))
		else
			-- TODO: for time table stuff
			if type(val) == 'table' then
				val = cjson.encode(val)
			end
			dev:set_input_prop(input.name, "value", val)
		end
	end

	if #pack.inputs == 1 then
		set_input(pack.inputs[1], data_value)
	else
		for _, input in ipairs(pack.inputs) do
			local val = data_value(input.offset)
			set_input(input, val)
		end
	end
end

function app:invalid_dev(dev, pack)
	for _, input in ipairs(pack.inputs) do
		dev:set_input_prop(input.name, "value", 0, nil, 1)
	end
end

function app:read_dev(dev, stat, addr, tpl)
	for _, pack in ipairs(tpl.packets) do
		self:read_packet(dev, stat, addr, pack)
	end
end

--- 应用运行入口
function app:run(tms)
	if not self._client then
		return
	end

	for _, dev in ipairs(self._devs) do
		self:read_dev(dev.dev, dev.stat, dev.addr, dev.tpl)
	end

	--- 返回下一次调用run之前的时间间隔
	return self._conf.loop_gap or 3000
end

--- 返回应用对象
return app
