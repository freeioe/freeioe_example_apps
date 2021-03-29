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

function worker:initialize(app, unit, dev, conf)
	self._log = app:log_api()
	self._unit = unit
	self._dev = dev
	self._conf = conf
	self._pdu = pdu:new()
	self._data_pack = data_pack:new()
	self._data_unpack = data_unpack:new()
end

function worker:run(modbus, plc_modbus)
	if plc_modbus then
		local r, err = self:plc_read(plc_modbus)
		if not r then
			return self:invalid_dev()
		end
	end
	local r, err = self:read_summary(modbus)
	if not r then
		return self:invalid_dev()
	end
end

function worker:plc_read_state(plc_modbus)
	local func = 0x03
	local start_addr = 3996
	local dlen = 1

	local req, err = self._pdu:make_request(func, start_addr, dlen)
	if not req then
		return nil, err
	end
	local pdu, err = modbus:request(self._unit, req, 1000)
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

	local plc_state = d:uint8(pdu_data, 1)
	self._plc_state = plc_state

	self._dev:set_input_prop('plc_state', 'value', plc_state)

	return true
end

function worker:plc_read_all(plc_modbus)
	local func = 0x03
	local start_addr = 4005
	local dlen = 5

	local req, err = self._pdu:make_request(func, start_addr, dlen)
	if not req then
		return nil, err
	end
	local pdu, err = modbus:request(self._unit, req, 1000)
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

	local flags = {
		0x100 = 'N',
		0x200 = 'D',
		0x800 = 'M',
		0x4000 = 'M',
	}
	local flag = flags[self._plc_state]
	local quality = self._plc_state ~= 0x100 and 1 or 0

	local pdu_data = string.sub(pdu, 3)

	local wet = d:uint16(pdu_data, 1)
	local dust = d:uint16(pdu_data, 3)
	local diff_pa = d:uint16(pdu_data, 5)
	local temp = d:uint16(pdu_data, 7)
	local pa_s = d:uint16(pdu_data, 9)

	wet = ((self._conf.wet_high - self._conf.wet_low) * wet ) / (27648 - 5530)
	dust = ((self._conf.dust_high - self._conf.dust_low) * dust ) / (27648 - 5530)
	diff_pa = ((self._conf.pa_high - self._conf.pa_low) * diff_pa ) / (27648 - 5530)
	temp = ((self._conf.temp_high - self._conf.temp_low) * temp ) / (27648 - 5530)
	pa_s = ((self._conf.pa_s_high - self._conf.pa_s_low) * pa_s ) / (27648 - 5530)

	local speed = (self._conf.Kv * self._conf.Pv * diff_pa) / math.sqrt(0.6025)

	self:set_input('wet', wet, nil, now, quality, flag)
	self:set_input('dust', dust, nil, now, quality, flag)
	self:set_input('speed', speed, nil, now, quality, flag)
	self:set_input('temp', temp, nil, now, quality, flag)
	self:set_input('pa_s', pa_s, nil, now, quality, flag)

	return true
end

function worker:invalid_dev()
	local quality = -1
	local flag = 'B'

	local now = ioe.time()
	-- PLC

	self._dev:set_input_prop('plc_state', 'value', 0, now, quality)
	self:set_input('flow', 0, 0, now, quality, flag)
	self:set_input('wet', 0, 0, now, quality, flag)
	self:set_input('dust', 0, 0, now, quality, flag)
	self:set_input('speed', 0, 0, now, quality, flag)
	self:set_input('temp', 0, 0, now, quality, flag)
	self:set_input('pa_s', 0, 0, now, quality, flag)

	-- 900UV
	self._dev:set_input_prop('error', "value", 0, now, quality)
	self._dev:set_input_prop('adjust', "value", 0, now, quality)
	self._dev:set_input_prop('maintain', "value", 0, now, quality)
	self:set_input('SO2', 0, 0, now, quality, flag)
	self:set_input('NO', 0, 0, now, quality, flag)
	self:set_input('O2', 0, nil, now, quality, flag)
	self:set_input('NO2', 0, 0, now, quality, flag)
	self:set_input('NOx', 0, 0, now, quality, flag)
end

function worker:calc_zs(Csn_dry, Cvo2_dry)
	return air_helper.Cz(Csn_dry, Cvo2_dry, self._a_s)
end

function worker:set_input(name, value, value_z, now, quality, flag)
	local rdata = {
		Rtd = value,
		ZsRtd = value_z,
		SampleTime = now,
		Flag = flag
	}
	self._dev:set_input_prop(name, 'value', value, now, quality)
	self._dev:set_input_prop(name, 'RDATA', cjson.encode(rdata), now, quality)
end

function worker:read_summary(modbus)
	local func = 0x03
	local start_addr = 10
	local dlen = 12

	local req, err = self._pdu:make_request(func, start_addr, dlen)
	if not req then
		return nil, err
	end
	local pdu, err = modbus:request(self._unit, req, 1000)
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

	local err = d:uint8(pdu_data, 1)
	local adjust = d:uint8(pdu_data, 2)
	local maintain = d:uint16(pdu_data, 3)

	local so2 = d:float(pdu_data, 5)
	local no = d:float(pdu_data, 9)
	local o2 = d:float(pdu_data, 13)
	local no2 = d:float(pdu_data, 17)
	local nox = d:float(pdu_data, 21)

	local so2_z = self:calc_zs(so2, o2)
	local no_z = self:calc_zs(no, o2)
	local no2_z = self:calc_zs(no2, o2)
	local nox_z = self:calc_zs(nox, o2)

	local now = ioe.time()

	self._dev:set_input_prop('error', "value", err, now, 0)
	self._dev:set_input_prop('adjust', "value", adjust, now, 0)
	self._dev:set_input_prop('maintain', "value", maintain, now, 0)

	local quality = err ~= 0 and 1 or 0
	local flag = err ~= 0 and 'D' or 'N'
	if flag == 'N' and adjust ~= 01 then
		flag = 'C'
	end
	if flag == 'N' and maintain ~= 0 then
		flag = 'M'
	end

	self:set_input('SO2', so2, so_z, now, quality, flag)
	self:set_input('NO', no, no_z, now, quality, flag)
	self:set_input('O2', o2, nil, now, quality, flag)
	self:set_input('NO2', no2, no2_z, now, quality, flag)
	self:set_input('NOx', nox, nox_z, now, quality, flag)
end

return worker
