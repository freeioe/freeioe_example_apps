--- 导入需要的模块
local modbus_master = require 'modbus.master.skynet'
local modbus_pdu = require 'modbus.pdu.init'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'

local csv_tpl = require 'csv_tpl'
local packet_split = require 'packet_split'
local conf_helper = require 'app.conf_helper'
local base_app = require 'app.base'
local basexx = require 'basexx'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = base_app:subclass("MODBUS_LUA_MASTER_APP")
--- 设定应用最小运行接口版本
app.static.API_VER = 5

--- 应用启动函数
function app:on_start()
	csv_tpl.init(self._sys:app_dir())

	---获取设备序列号和应用配置
	local sys_id = self._sys:id()

	local config = self._conf or {}
	--[[
	config.devs = config.devs or {
		{ unit = 1, name = 'bms01', sn = 'xxx-xx-1', tpl = 'bms' },
		{ unit = 2, name = 'bms02', sn = 'xxx-xx-2', tpl = 'bms2' }
	}
	]]--

	--- 获取云配置
	if not config.devs or config.cnf then
		if not config.cnf then
			config = 'CNF000000002.1' -- loading cloud configuration CNF000000002 version 1
		else
			config = config.cnf .. '.' .. config.ver
		end
	end

	local helper = conf_helper:new(self._sys, config)
	helper:fetch()

	self._pdu = modbus_pdu:new()
	self._data_pack = data_pack:new()
	self._data_unpack = data_unpack:new()
	self._split = packet_split:new(self._data_pack, self._data_unpack)

	self._devs = {}
	for _, v in ipairs(helper:devices()) do
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

			local inputs = {}
			local outputs = {}
			local tpl_inputs = {}
			local tpl_outputs = {}
			for _, v in ipairs(tpl.props) do
				if string.find(v.rw, '[Rr]') then
					inputs[#inputs + 1] = {
						name = v.name,
						desc = v.desc,
						vt = v.vt,
						unit = v.unit,
					}
					tpl_inputs[#tpl_inputs + 1] = v
				end
				if string.find(v.rw, '[Ww]') then
					outputs[#outputs + 1] = {
						name = v.name,
						desc = v.desc,
						unit = v.unit,
					}
					tpl_outputs[#tpl_outputs + 1] = v
				end
			end

			local packets = self._split:split(tpl.props)

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
				packets = packets,
				inputs = tpl_inputs,
				outputs = tpl_outputs,
			})
		end
	end

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
			port = "/tmp/ttyS1",
			baudrate = 19200
		}
	end
	if conf.channel_type == 'socket' then
		self._modbus = modbus_master('tcp', {link='tcp', tcp=conf.opt})
	else
		self._modbus = modbus_master('rtu', {link='serial', serial=conf.opt})
	end

	--- 设定通讯口数据回调
	self._modbus:set_io_cb(function(io, unit, msg)
		self._log:trace(io, basexx.to_hex(msg))
		local dev = nil
		for _, v in ipairs(self._devs) do
			if v.unit == unit then
				dev = v
				break
			end
		end
		--- 输出通讯报文
		
		if dev then
			dev.dev:dump_comm(io, msg)
			--- 计算统计信息
			if io == 'IN' then
				dev.stat:inc('bytes_in', string.len(msg))
			else
				dev.stat:inc('bytes_out', string.len(msg))
			end
		else
			self._sys:dump_comm(sys_id, io, msg)
		end
	end)

	self._modbus:start()

	return true
end

--- 应用退出函数
function app:on_close(reason)
	if self._modbus then
		self._modbus:close()
		self._modbus = nil
	end
	print(self._name, reason)
end

function app:on_output(app_src, sn, output, prop, value, timestamp)
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
	for _, v in ipairs(dev.outputs or {}) do
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
	
	local r, err = self:write_packet(dev.dev, dev.stat, dev.unit, tpl_output, value)
	--[[
	if not r then
		local info = "Write output failure!"
		local data = { sn=sn, output=output, prop=prop, value=value, err=err }
		self._dev:fire_event(event.LEVEL_ERROR, event.EVENT_DEV, info, data)
	end
	]]--
	return r, err
end

function app:write_packet(dev, stat, unit, output, value)
	--- 设定写数据的地址
	local func = tonumber(output.wfc) or 0x06
	local addr = output.addr

	local timeout = output.timeout or 5000

	local val = value / output.rate
	if output.dt ~= 'float' and output.dt ~= 'double' then
		val = math.floor(val + 0.5)
	end

	local req = nil
	local err = nil

	if output.wfc == 0x06 then
		req, err = self._pdu:make_request(func, addr, val)
	elseif output.wfc == 0x05 then
		req, err = self._pdu:make_request(func, addr, val ~= 0)
	else
		local dpack = self._data_pack
		local data = dpack[output.dt](dpack, val)
		req, err = self._pdu:make_request(func, addr, string.len(data), data)
	end

	if not req then
		self._log:warning("Failed to build modbus request, error:", err)
		return self:invalid_dev(dev, pack)
	end

	--- 写入数据
	stat:inc('packets_out', 1)
	local pdu, err = self._modbus:request(unit, req, timeout)

	if not pdu then 
		self._log:warning("write failed: " .. err) 
		return nil, err
	end

	--- 统计数据
	stat:inc('packets_in', 1)

	return true
end

function app:read_packet(dev, stat, unit, pack)
	assert(dev and stat and unit)
	--- 设定读取的起始地址和读取的长度
	local func = pack.fc or 0x03 -- 03指令
	local addr = pack.start or 0x00
	local len = pack.len or 10 -- 长度

	--- 读取数据
	local timeout = pack.timeout or 5000
	local req, err = self._pdu:make_request(func, addr, len)
	if not req then
		self._log:warning("Failed to build modbus request, error:", err)
		return self:invalid_dev(dev, pack)
	end


	--- 统计数据
	stat:inc('packets_out', 1)

	--self._log:debug("Before request", unit, func, addr, len, timeout)
	local pdu, err = self._modbus:request(unit, req, timeout)
	if not pdu then
		self._log:warning("read failed: " .. (err or "Timeout"))
		return self:invalid_dev(dev, pack)
	end
	--self._log:trace("read input registers done!", unit)

	--- 统计数据
	stat:inc('packets_in', 1)

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		self._log:warning("read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1)))
		return
	end

	local len = d:uint8(pdu, 2)
	--assert(len >= pack.len * 2)
	local pdu_data = string.sub(pdu, 3)

	for _, input in ipairs(pack.inputs) do
		--print(input.name, input.addr, input.pack_index)
		local val = pack.unpack(input, pdu_data)
		--print(val)
		if input.rate and input.rate ~= 1 then
			val = val * input.rate
			dev:set_input_prop(input.name, "value", val)
		else
			dev:set_input_prop(input.name, "value", math.tointeger(val))
		end
	end
end

function app:invalid_dev(dev, pack)
	for _, input in ipairs(pack.inputs) do
		dev:set_input_prop(input.name, "value", 0, nil, 1)
	end
end

function app:read_dev(dev, stat, unit, packets)
	for _, pack in ipairs(packets) do
		self:read_packet(dev, stat, unit, pack)
	end
end

--- 应用运行入口
function app:on_run(tms)
	if not self._modbus then
		return
	end

	for _, dev in ipairs(self._devs) do
		self:read_dev(dev.dev, dev.stat, dev.unit, dev.packets)
	end

	--- 返回下一次调用run之前的时间间隔
	return self._conf.loop_gap or 5000
end

--- 返回应用对象
return app
