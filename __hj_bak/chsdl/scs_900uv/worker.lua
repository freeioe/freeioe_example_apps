local class = require 'middleclass'
local pdu = require 'modbus.pdu.init'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'
local bcd = require 'bcd'
local ioe = require 'ioe'
local retry = require 'utils.retry'

local worker = class("SCS-900UV.worker")

local SF = string.format

--[[
HJ212-RS:
0-关闭 1-运行 2-校准 3-维护 4-报警 5-反吹

HJ212 Flag:
N-正常 F-停运 M-维护 S-手工输入 D-故障 C-校准 T-超限 B-通讯异常

i12001 / i12007:
0=运行  1=维护  2=故障  3=校准（校标，校零)  5=反吹 6=标定

i12003 / i12009:
0=正常  1=气路堵塞  2=上限报警  3=下限报警  4=缺仪表风  5=温控报警  6=光强弱报警  7=伴热管温度报警  8=氧传感器老化报警 9=探头温度故障
]]--
-- Returns RS, infos, flag
local function convert_status(alarm, adjust, maintain)
	local rs = 1
	local flag = 'N'
	if rs == 1 and alarm ~= 0 then
		rs = 4
		flag = 'D'
	end
	if rs == 1 and adjust ~= 1 then
		rs = 2
		flag = 'C'
	end
	if rs == 1 and maintain ~= 0 then
		rs = 3
		flag = 'M'
	end
	local i12001 = 0
	if i12001 == 0 and alarm ~= 0 then
		i12001 = 2
	end
	if i12001 == 0 and adjust ~= 1 then
		i12001 = 3
	end
	if i12001 == 0 and maintain ~= 0 then
		i12001 = 1
	end

	local alarm = tonumber(alarm)
	local infos = {
		a19001 = {},
		a21002 = {},
		a21003 = {},
		a21004 = {},
		a21026 = {}
	}

	for k, v in pairs(infos) do
		v.i12001 = i12001
		v.i12002 = alarm == 0 and 0 or 1
		v.i12003 = alarm == 0 and 0 or 99  -- other
		--v.i12007 = i12001
		--v.i12008 = alarm == 0 and 0 or 1
		--v.i12009 = alarm == 0 and 0 or nil  -- other
	end

	local set_alarm = function(val)
		for k, v in pairs(infos) do
			v.i12003 = val
			--v.i12009 = val
		end
	end

	if alarm == 0 then
		-- Already been initialized
		--set_alarm(0)
	else
		-- TODO: Alarm infomration
		--set_alarm(99)
		if 0x40 == (alarm & 0x40) then
			infos.a19001.i12009 = 8
		end

	end

	return rs, infos, flag
end

local function map_info(key, infos, info)
	local t = infos[key] or {}
	for k, v in pairs(t) do
		assert(info[k] == nil)
		info[k] = v
	end
	return info
end

local function bcd_num(pdu_data, index)
	return bcd.decode(string.sub(pdu_data, index, index))
end

local function convert_datetime(pdu_data, index)
	local year = bcd_num(pdu_data, index)
	local mon = bcd_num(pdu_data, index + 1)
	local day = bcd_num(pdu_data, index + 2)
	local hour = bcd_num(pdu_data, index + 3)
	local min = bcd_num(pdu_data, index + 4)
	local sec = bcd_num(pdu_data, index + 5)

	local t = os.time({
		year = 2000 + year,
		month = mon,
		day = day,
		hour = hour,
		min = min,
		sec = sec
	})
	--print(os.date('%FT%T', t))

	return t
end

function worker:initialize(app, unit, dev, conf)
	self._log = app:log_api()
	self._unit = unit
	self._dev = dev
	self._conf = conf
	self._pdu = pdu:new()
	self._data_pack = data_pack:new()
	self._data_unpack = data_unpack:new()
end

function worker:run(modbus)
	local r, err = self:read_val(modbus)
	if not r then
		return self:invalid_dev()
	end
end

function worker:invalid_dev()
	local quality = -1
	local flag = 'B'

	local now = ioe.time()

	self._dev:set_input_prop('RS', "value", 0, now, quality)
	self._dev:set_input_prop('alarm', "value", -1, now, quality)
	self._dev:set_input_prop('adjust', "value", -1, now, quality)
	self._dev:set_input_prop('maintain', "value", -1, now, quality)

	self:set_input('a19001', 0, nil, now, quality, flag) -- O2
	self:set_input('a21002', 0, nil, now, quality, flag) -- NOx
	self:set_input('a21003', 0, nil, now, quality, flag) -- NO
	self:set_input('a21004', 0, nil, now, quality, flag) -- NO2
	self:set_input('a21026', 0, nil, now, quality, flag) -- SO2
end

local function map_info_without_raw(info)
	local ret = {}
	for k, v in pairs(info) do
		if k ~= i13011 then
			ret[k] == v
		end
	end
	return ret
end

function worker:set_input(name, value, info, now, quality, flag)
	if info then
		local rinfo = map_info_without_raw(info)
		self._dev:set_input_prop(name, 'INFO', rinfo, now, quality)
	end

	local rdata = {
		value = value,
		value_src = info and info.i13011 or nil,
		timestamp = now,
		flag = flag
	}
	self._dev:set_input_prop(name, 'value', value, now, quality)
	self._dev:set_input_prop(name, 'RDATA', rdata, now, quality)
	for k, v in pairs(info) do
		self._dev:set_input_prop(name .. '-' .. k, 'value', v, now, quality)
	end
end

function worker:read_val(modbus)
	local func = 0x03
	local start_addr = 10
	local dlen = 12

	local req, err = self._pdu:make_request(func, start_addr, dlen)
	if not req then
		return nil, err
	end

	--- Retry request in three times
	local pdu, err = retry(3, modbus.request, modbus, self._unit, req, 1000)
	if not pdu then
		return nil, err
	end

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		local err = "read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1))
		self._log:warning(err)
		return nil, err
	end

	local len = d:uint8(pdu, 2)
	assert(len >= dlen * 2, SF("length issue :%d - %d", len, dlen * 2))

	local pdu_data = string.sub(pdu, 3)

	local alarm = d:uint8(pdu_data, 1)
	local adjust = d:uint8(pdu_data, 2)
	local maintain = d:uint16(pdu_data, 3)

	local rs, infos, flag = convert_status(alarm, adjust, maintain)

	local so2 = d:float(pdu_data, 5)
	local no = d:float(pdu_data, 9)
	local o2 = d:float(pdu_data, 13)
	local no2 = d:float(pdu_data, 17)
	local nox = d:float(pdu_data, 21)

	local now = ioe.time()

	self._dev:set_input_prop('RS', 'value', rs, now, 0)
	self._dev:set_input_prop('alarm', "value", alarm, now, 0)
	self._dev:set_input_prop('adjust', "value", adjust, now, 0)
	self._dev:set_input_prop('maintain', "value", maintain, now, 0)

	local quality = 0

	local so2_info, err = self:read_SO2_info()
	if so2_info then
		self._so2_info = map_info('a21026', infos, so2_info)
	else
		self._log:error("Read SO2 info error", err)
	end
	local no_info, err = self:read_NO_info()
	if no_info then
		self._no_info = map_info('a21003', infos, no_info)
	else
		self._log:error("Read NO info error", err)
	end
	local o2_info, err = self:read_O2_info()
	if o2_info then
		self._o2_info = map_info('a19001', infos, o2_info)
	else
		self._log:error("Read O2 info error", err)
	end
	local no2_info, err = self:read_NO2_info()
	if no2_info then
		self._no2_info = map_info('a21004', infos, no2_info)
	else
		self._log:error("Read NO2 info error", err)
	end

	self:set_input('a19001', o2, self._o2_info, now, quality, flag) -- O2
	self:set_input('a21002', nox, nil, now, quality, flag) -- NOx
	self:set_input('a21003', no, self._no_info, now, quality, flag) -- NO
	self:set_input('a21004', no2, self._no2_info, now, quality, flag) -- NO2
	self:set_input('a21026', so2, self._so2_info, now, quality, flag) -- SO2
end

function worker:read_SO2_info(modbus)
	local func = 0x03
	local start_addr = 22
	local dlen = 21

	local req, err = self._pdu:make_request(func, start_addr, dlen)
	if not req then
		return nil, err
	end

	--- Retry request in three times
	local pdu, err = retry(3, modbus.request, modbus, self._unit, req, 1000)
	if not pdu then
		return nil, err
	end

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		local err = "read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1))
		self._log:warning(err)
		return nil, err
	end

	local len = d:uint8(pdu, 2)
	assert(len >= dlen * 2, SF("length issue :%d - %d", len, dlen * 2))

	local pdu_data = string.sub(pdu, 3)

	return {
		i13006 = d:float(pdu_data, 1),
		i13011 = d:float(pdu_data, 5),
		i13013 = d:uint16(pdu_data, 9),
		i13008 = d:float(pdu_data, 11),
		i13007 = convert_datetime(pdu_data, 15),
		i13001 = convert_datetime(pdu_data, 21),
		i13005 = d:float(pdu_data, 35),
		i13010 = d:float(pdu_data, 39), -- 42 bytes
	}
end

function worker:read_NO_info(modbus)
	local func = 0x03
	local start_addr = 43
	local dlen = 21

	local req, err = self._pdu:make_request(func, start_addr, dlen)
	if not req then
		return nil, err
	end

	--- Retry request in three times
	local pdu, err = retry(3, modbus.request, modbus, self._unit, req, 1000)
	if not pdu then
		return nil, err
	end

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		local err = "read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1))
		self._log:warning(err)
		return nil, err
	end

	local len = d:uint8(pdu, 2)
	assert(len >= dlen * 2, SF("length issue :%d - %d", len, dlen * 2))

	local pdu_data = string.sub(pdu, 3)

	return {
		i13006 = d:float(pdu_data, 1),
		i13011 = d:float(pdu_data, 5),
		i13013 = d:uint16(pdu_data, 9),
		i13008 = d:float(pdu_data, 11),
		i13007 = convert_datetime(pdu_data, 15),
		i13001 = convert_datetime(pdu_data, 21),
		i13005 = d:float(pdu_data, 35),
		i13010 = d:float(pdu_data, 39), -- 42 bytes
	}
end

function worker:read_O2_info(modbus)
	local func = 0x03
	local start_addr = 64
	local dlen = 23

	local req, err = self._pdu:make_request(func, start_addr, dlen)
	if not req then
		return nil, err
	end

	--- Retry request in three times
	local pdu, err = retry(3, modbus.request, modbus, self._unit, req, 1000)
	if not pdu then
		return nil, err
	end

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		local err = "read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1))
		self._log:warning(err)
		return nil, err
	end

	local len = d:uint8(pdu, 2)
	assert(len >= dlen * 2, SF("length issue :%d - %d", len, dlen * 2))

	local pdu_data = string.sub(pdu, 3)

	return {
		i13013 = d:uint16(pdu_data, 1),
		i13008 = d:float(pdu_data, 3),
		i13007 = convert_datetime(pdu_data, 7),
		i13001 = convert_datetime(pdu_data, 13),
		i13005 = d:float(pdu_data, 27),
		i13010 = d:float(pdu_data, 31),
		i13004 = d:uint16(pdu_data, 35),
		i13006 = d:float(pdu_data, 37),
		i13011 = d:uint16(pdu_data, 41),
		i13011_b = d:uint32(pdu_data, 43), -- 46 bytes
	}
end

function worker:read_NO2_info(modbus)
	local func = 0x03
	local start_addr = 93
	local dlen = 21

	local req, err = self._pdu:make_request(func, start_addr, dlen)
	if not req then
		return nil, err
	end

	--- Retry request in three times
	local pdu, err = retry(3, modbus.request, modbus, self._unit, req, 1000)
	if not pdu then
		return nil, err
	end

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		local err = "read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1))
		self._log:warning(err)
		return nil, err
	end

	local len = d:uint8(pdu, 2)
	assert(len >= dlen * 2, SF("length issue :%d - %d", len, dlen * 2))

	local pdu_data = string.sub(pdu, 3)

	return {
		i13006 = d:float(pdu_data, 1),
		i13011 = d:float(pdu_data, 5),
		i13013 = d:uint16(pdu_data, 9),
		i13008 = d:float(pdu_data, 11),
		i13007 = convert_datetime(pdu_data, 15),
		i13001 = convert_datetime(pdu_data, 21),
		i13005 = d:float(pdu_data, 35),
		i13010 = d:float(pdu_data, 39), -- 42 bytes
	}
end


return worker
