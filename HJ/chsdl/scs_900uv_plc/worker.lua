local class = require 'middleclass'
local cjson = require 'cjson.safe'
local pdu = require 'modbus.pdu.init'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'
local bcd = require 'bcd'
local ioe = require 'ioe'
local air_helper = require 'hj212.calc.air_helper'

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
-- Returns RS, flag, i12001, i12003
local function convert_status(status)
	local rs = 1
	local flag = 'N'
	local i12001 = 0
	local i12003 = 0
	if status & 0x0100 ~= 0 then
		-- Initial values
	end
	if status & 0x0200 ~= 0 then
		rs = 4
		flag = 'D'
		i12001 = 2
		i12003 = 99
	end
	if status & 0x0800 ~= 0 then
		rs = 3
		flag = 'M'
		i12001 = 1
		i12003 = 0
	end
	if status & 0x4000 ~= 0 then
		rs = 5
		flag = 'M'
		i12001 = 5
		i12003 = 0
	end

	return rs, flag, i12001, i12003
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

function worker:read_settings()
	local station = self._conf.station or 'HJ212'

	if not self._settings then
		log:info("Wait for HJ212 Settings")
	end

	self._settings = ioe.env.wait('HJ212.SETTINGS', station)

	if self._settings.__time ~= self._last_stime then
		log:info("Got HJ212 Settings! Value:")
		log:info(cjson.encode(self._settings))
		self._last_stime = self._settings.__time
	end
end

function worker:run(modbus)
	-- Read settings
	self:read_settings()

	local status, err = self:read_status(modbus)
	if not status then
		return self:invalid_dev()
	end
	self._plc_status = r
	local r, err = self:read_val(modbus)
	return r, err
end

function worker:read_status(modbus)
	local func = 0x03
	local start_addr = 3996
	local dlen = 1

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

	local plc_status = d:uint8(pdu_data, 1)

	return plc_status
end

function worker:read_val(modbus)
	local func = 0x03
	local start_addr = 4005
	local dlen = 5

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

	local now = ioe.time()
	local quality = 0
	assert(self._status)
	local rs, flag, i12001, i12003 = convert_status(self._status)

	local pdu_data = string.sub(pdu, 3)

	local wet = d:uint16(pdu_data, 1)
	local dust = d:uint16(pdu_data, 3)
	local diff_pa = d:uint16(pdu_data, 5)
	local temp = d:uint16(pdu_data, 7)
	local pa_s = d:uint16(pdu_data, 9)

	local humidity_min = settings[self._conf.humidity_prefix..'_Min'] or 0
	local humidity_max = settings[self._conf.humidity_prefix..'_Max'] or 100
	local dust_min = settings[self._conf.dust_prefix..'_Min'] or 0
	local dust_max = settings[self._conf.dust_prefix..'_Max'] or 100
	local pressure_min = settings[self._conf.pressue_prefix..'_Min'] or 0
	local pressure_max = settings[self._conf.pressue_prefix..'_Max'] or 100
	local temp_min = settings[self._conf.temp_prefix..'_Min'] or 0
	local temp_max = settings[self._conf.temp_prefix..'_Max'] or 100
	local delta_pressure_min = settings[self._conf.delta_pressure_prefix..'_Min'] or 0
	local delta_pressure_max = settings[self._conf.delta_pressure_prefix..'_Max'] or 100


	local a01014 = ((humidity_max - humidity_min) * (wet - 5530) ) / (27648 - 5530)
	local a34013 = ((dust_max - dust_min) * (dust - 5530) ) / (27648 - 5530)
	local speed = ((delta_pressure_max - delta_pressure_min) * (diff_pa - 5530) ) / (27648 - 5530)
	local a01012 = ((temp_max - temp_min) * (temp - 5530) ) / (27648 - 5530)
	local a01013 = ((pressure_max - pressure_min) * (pa_s - 5530) ) / (27648 - 5530)

	local Kv = assert(settings.Kv)
	local Kp = assert(settings.Kp)
	local Ba = assert(settings.Ba)
	local a01011 = (Kv * Kp * speed) / math.sqrt(0.6025)
	--- 计算标干流量
	a01011 = a01011 * ((a01013 * 1000 + Ba) / 101325) * ( 273 / (273 + a01012)) * ( 1 - a01014)

	self._dev:set_input_prop('RS', "value", rs, now, quality)
	self._dev:set_input_prop('status', "value", status, now, quality)

	local infos = {
		a01014 = {i13011 = wet},
		a34013 = {i13011 = dust},
		a01011 = {i13011 = diff_pa},
		a01012 = {i13011 = temp},
		a01013 = {i13011 = pa_s},
	}
	for k, v in pairs(infos) do
		v.i12001 = i12001
		v.i12002 = i12003 == 0 and 0 or 1
		v.i12003 = i12003
	end

	self:set_input('a01014', a01014, infos.a01014, now, quality, flag)
	self:set_input('a34013', a34013, infos.a34013, now, quality, flag)
	self:set_input('a01011', a01011, infos.a01011, now, quality, flag)
	self:set_input('a01012', a01012, infos.a01012, now, quality, flag)
	self:set_input('a01013', a01013, infos.a01013, now, quality, flag)

	return true
end

function worker:invalid_dev()
	local quality = -1
	local flag = 'B'
	local quality = -1
	local flag = 'B'

	local now = ioe.time()

	self._dev:set_input_prop('RS', "value", 0, now, quality)

	self._dev:set_input_prop('status', "value", -1, now, quality)

	self:set_input('a34013', 0, nil, now, quality, flag)
	self:set_input('a01011', 0, nil, now, quality, flag)
	self:set_input('a01012', 0, nil, now, quality, flag)
	self:set_input('a01013', 0, nil, now, quality, flag)
	self:set_input('a01014', 0, nil, now, quality, flag)
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


return worker
