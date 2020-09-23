--- 导入需要的模块
local modbus_master = require 'modbus.master.skynet'
local modbus_pdu = require 'modbus.pdu.init'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'
local queue = require 'skynet.queue'

local csv_tpl = require 'csv_tpl'
local packet_split = require 'packet_split'
local valid_value = require 'valid_value'
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
	if not config.devs and config.cnf and conf.ver then
		config = config.cnf .. '.' .. config.ver
	end

	--[[ test
	if not config.cnf then
		config = 'CNF000000003.1' -- loading cloud configuration CNF000000002 version 1
	end
	]]--

	local helper = conf_helper:new(self._sys, config)
	helper:fetch()

	self._pdu = modbus_pdu:new()
	self._data_pack = data_pack:new()
	self._data_unpack = data_unpack:new()
	self._split = packet_split:new(self._data_pack, self._data_unpack)

	local dev_sn_prefix = config.dev_sn_prefix ~= nil and config.dev_sn_prefix or true

	self._devs = {}
	for _, v in ipairs(helper:devices()) do
		assert(v.sn and v.name and v.unit and v.tpl)

		--- 生成设备的序列号
		local dev_sn = dev_sn_prefix and sys_id.."."..v.sn or v.sn
		self._log:debug("Loading template file", v.tpl)
		local tpl, err = csv_tpl.load_tpl(v.tpl, function(...) self._log:error(...) end)
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

			local packets = self._split:split(tpl_inputs)

			--- 生成设备对象
			local dev = self._api:add_device(dev_sn, meta, inputs, outputs)
			--- 生成设备通讯口统计对象
			local stat = dev:stat('port')

			table.insert(self._devs, {
				unit = tonumber(v.unit) or 0,
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
		conf.opt = conf.socket_opt or {
			host = "127.0.0.1",
			port = 1503,
			nodelay = true
		}
	else
		conf.opt = conf.serial_opt or {
			port = "/tmp/ttyS1",
			baudrate = 19200
		}
	end
	self._loop_gap = conf.loop_gap or self._conf.loop_gap

	if conf.channel_type == 'socket' then
		self._modbus = modbus_master(string.lower(conf.apdu_type or 'tcp'), {link='tcp', tcp=conf.opt})
		self._block = string.lower(conf.apdu_type or 'tcp') ~= 'tcp'
	else
		self._modbus = modbus_master(string.lower(conf.apdu_type or 'rtu'), {link='serial', serial=conf.opt})
		self._block = true
	end
	if self._block then
		self._queue = queue()
	else
		-- fake queue
		self._queue = function(f, ...)
			return f(...)
		end
	end

	--- 设定通讯口数据回调
	self._modbus:set_io_cb(function(io, unit, msg)
		--[[
		if string.lower(conf.apdu_type) == 'ascii' then
			self._log:trace(io, msg)
		else
			self._log:trace(io, basexx.to_hex(msg))
		end
		]]--

		local dev = nil
		for _, v in ipairs(self._devs) do
			if v.unit == tonumber(unit) then
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

	return self._modbus:start()
end

--- 应用退出函数
function app:on_close(reason)
	local close_modbus = function()
		if self._modbus then
			self._modbus:stop()
			self._modbus = nil
		end
	end
	if self._queue then
		self._log:debug("Wait for reading queue finished")
		self._queue(function()
			self._log:debug("Reading queue finished!")
			close_modbus()
		end)
	else
		close_modbus()
	end
end

function app:on_output(app_src, sn, output, prop, value, timestamp)
	if prop ~= 'value' then
		return false, "Cannot write property which is not value"
	end

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

	local val = value
	if tpl_output.rate and tpl_output.rate ~= 1 then
		val = val / tpl_output.rate
	end

	local val, err = valid_value(tpl_output.dt, val)
	if not val then
		self._log:error("Write value validation", err)
		return false, err
	end

	--- UINT8, INT8 hacks
	if tpl_output.dt == 'int8' or tpl_output.dt == 'uint8' then
		local link_val = 0
		local link_offset = tpl_output.offset == 1 and 0 or 1
		for _, v in ipairs(dev.inputs) do
			--- Check function code and addr and offset
			if v.fc == tpl_output.fc and v.addr == tpl_output.addr and v.offset == link_offset then
				-- check data type
				if v.dt == 'uint8' or v.dt == 'int8' then
					link_val = dev.dev:get_input_prop(v.name, 'value')
					if v.rate ~= 1 then
						link_val = link_val / v.rate
					end
					if tpl_output.dt ~= v.dt then
						if tpl_output.dt == 'uint8' then
							link_val = (link_val + 256) % 256
						else
							link_val = (link_val - 128) % 256 - 128
						end
					end
				end
			end
		end
		--- TODO: Take care about little endian stuff?????
		if link_offset == 1 then
			val = (val << 8 ) + link_val
		else
			val = (link_val << 8) + val
		end
	end
	--- hacks end

	if tpl_output.dt == 'bit' and tpl_output.wfc == 0x06 then
		return nil, "Bit value readed from 0x03/0x04 cannot be write to device"
	end

	local r, err = self._queue(self.write_packet, self, dev.dev, dev.stat, dev.unit, tpl_output, val)
	--[[
	if not r then
		local info = "Write output failure!"
		local data = { sn=sn, output=output, prop=prop, value=value, err=err }
		self._dev:fire_event(event.LEVEL_ERROR, event.EVENT_DEV, info, data)
	end
	]]--
	return r, err or "Done"
end

function app:write_packet(dev, stat, unit, output, value)
	--- 设定写数据的地址
	local func = tonumber(output.wfc) or 0x06
	local addr = output.addr

	if not self._modbus then
		return
	end

	local timeout = output.timeout or 5000

	local req = nil
	local err = nil

	if output.wfc == 0x06 or output.wfc == 0x05 then
		req, err = self._pdu:make_request(func, addr, value)
	else
		local dpack = self._data_pack
		local data = dpack[output.dt](dpack, value)
		req, err = self._pdu:make_request(func, addr, data)
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

	return true, "Write Done!"
end

function app:read_packet(dev, stat, unit, pack)
	assert(dev and stat and unit)
	--- 设定读取的起始地址和读取的长度
	local func = pack.fc or 0x03 -- 03指令
	local addr = pack.start or 0x00
	local len = pack.len or 10 -- 长度

	if not self._modbus then
		return
	end

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
		if unit == 11 then
			print(unit, input.name, input.addr, input.pack_index)
		end
		local val, err = pack.unpack(input, pdu_data)
		if unit == 11 then
			print(unit, input.name, val)
		end
		if val == nil then
			assert(false, err or 'val is nil')
		end
		if unit == 11 and val == 0 then
			self._log:error("Value is zeor", input.name)
		end
		if input.rate and input.rate ~= 1 then
			val = val * input.rate
		end
		dev:set_input_prop(input.name, "value", val)
	end
end

function app:invalid_dev(dev, pack)
	for _, input in ipairs(pack.inputs) do
		dev:set_input_prop(input.name, "value", 0, nil, 1)
	end
end

function app:read_dev(dev, stat, unit, packets)
	for _, pack in ipairs(packets) do
		self._queue(self.read_packet, self, dev, stat, unit, pack)
	end
end

--- 应用运行入口
function app:on_run(tms)
	if not self._modbus then
		return
	end

	for _, dev in ipairs(self._devs) do
		if not self._modbus then
			break
		end
		self:read_dev(dev.dev, dev.stat, dev.unit, dev.packets)
	end

	return self._loop_gap or 5000
end

--- 返回应用对象
return app
