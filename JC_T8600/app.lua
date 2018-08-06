local class = require 'middleclass'
--- 导入需要的模块
local modbus = require 'modbus.init'
local sm_client = require 'modbus.skynet_client'
local socketchannel = require 'socketchannel'
local serialchannel = require 'serialchannel'
local csv_tpl = require 'csv_tpl'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("XXXX_App")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 1

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
		--port = "/dev/ttymxc1",
		port = "/tmp/ttyS10",
		baudrate = 9600,
		data_bits = 8,
		stop_bits = 1,
	}

	config.devs = config.devs or {
		{ unit = 1, name = 'T8600_1', sn = 'xxx-xx-1', tpl = 'T8600' },
		{ unit = 2, name = 'T8600_2', sn = 'xxx-xx-2', tpl = 'T8600' },
	}

	self._devs = {}
	for _, v in ipairs(config.devs) do
		assert(v.sn and v.name and v.unit and v.tpl)

		--- 生成设备的序列号
		local dev_sn = sys_id.."."..v.sn
		local tpl, err = csv_tpl.load_tpl(v.tpl)
		if not tpl then
			self._log:error("loading csv tpl failed", err)
		else
			local meta = self._api:default_meta()
			meta.name = tpl.meta.name or "Modbus"
			meta.description = tpl.meta.desc or "Modbus Device"
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
			inputs[#inputs + 1] = { name = "status", desc = "设备状态", vt="int"}
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
				unit = v.unit,
				sn = dev_sn,
				dev = dev,
				tpl = tpl,
				stat = stat,
			})
		end
	end

	--- 打开串口
	local client = sm_client(serialchannel, config.opt, modbus.apdu_rtu, 1)
	self._client = client

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
	
	return self:write_package(dev.dev, dev.stat, dev.unit, tpl_output, value)
end

function app:write_packet(dev, stat, unit, output, value)
	--- 设定写数据的地址
	local req = {
		func = tonumber(output.func) or 0x03, -- 03指令
		addr = output.addr, -- 地址
		unit = unit or output.unit,
		len = output.len or 1,
	}
	local d = modbus.decode
	local df = d[output.dt]
	assert(df)

	local val = math.floor(value * (1/output.rate))
	req.data = table.concat({ df(val) })
	
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
	local val_ret = df(pdu, 0)

	return val_ret == val
end

function app:read_packet(dev, stat, unit, pack)
	--- 设定读取的起始地址和读取的长度
	local base_address = pack.saddr or 0x00
	local req = {
		func = tonumber(pack.func) or 0x03, -- 03指令
		addr = base_address, -- 起始地址
		len = pack.len or 10, -- 长度
		unit = unit or pack.unit
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
		return self:invalid_dev(dev, pack)
	end

	if not pdu then 
		self._log:warning("read failed: " .. err) 
		return self:invalid_dev(dev, pack)
	end

	--- 统计数据
	self._log:trace("read input registers done!", unit)
	stat:inc('packets_in', 1)

	--- 解析数据
	local d = modbus.decode
	local len = d.uint8(pdu, 2)
	--assert(len >= 38 * 2)

	for _, input in ipairs(pack.inputs) do
		local df = d[input.dt]
		assert(df)
		local index = input.saddr
		local val = df(pdu, index + 2)
		if input.rate and input.rate ~= 1 then
			val = val * input.rate
			dev:set_input_prop(input.name, "value", val)
		else
			dev:set_input_prop(input.name, "value", math.tointeger(val))
		end
	end
	dev:set_input_prop('status', 'value', 0)
end

function app:invalid_dev(dev, pack)
	for _, input in ipairs(pack.inputs) do
		dev:set_input_prop(input.name, "value", 0, nil, 1)
	end
	dev:set_input_prop('status', 'value', 1, nil, 1)
end

function app:read_dev(dev, stat, unit, tpl)
	for _, pack in ipairs(tpl.packets) do
		self:read_packet(dev, stat, unit, pack)
	end
end

--- 应用运行入口
function app:run(tms)
	if not self._client then
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
