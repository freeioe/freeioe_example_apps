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
		self:plc_read(modbus)
	end
	local r, err = self:read_summary(modbus)
	if not r then
		self:invalid_dev()
	end
end

function worker:invalid_dev()
	local quality = -1
	local flag = 'B'

	local now = ioe.time()
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

	local req, err = self._pdu:make_request(func, start_addr, 12)
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
	assert(len >= 16 * 2, SF("length issue :%d - %d", len, 16 * 2))

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
