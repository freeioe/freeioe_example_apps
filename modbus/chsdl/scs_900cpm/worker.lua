local class = require 'middleclass'
local cjson = require 'cjson.safe'
local pdu = require 'modbus.pdu.init'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'
local bcd = require 'bcd'
local ioe = require 'ioe'

local worker = class("SCS-900CPM.worker")

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
	local r, err = self:read_summary(modbus)
	if not r then
		self:invalid_dev()
	end
end

function worker:invalid_dev()
	local quality = -1
	local flag = 'B'

	local now = ioe.time()
	self._dev:set_input_prop('state', "value", 0, now, quality)
	self._dev:set_input_prop('r1', "value", 0, now, quality)
	self._dev:set_input_prop('r2', "value", 0, now, quality)
	self._dev:set_input_prop('k1', "value", 0, now, quality)
	self._dev:set_input_prop('t1', "value", 0, now, quality)
	self._dev:set_input_prop('range', "value", 0, now, quality)
	self._dev:set_input_prop('dust_raw', "value", 0, now, quality)

	self:set_input('dust', 0, nil, now, quality, flag)
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
	local start_addr = 0

	local req, err = self._pdu:make_request(func, start_addr, 15)
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

	local dust = d:float(pdu_data, 1)
	local r1 = d:float(pdu_data, 5)
	local r2 = d:float(pdu_data, 9)
	local k1 = d:float(pdu_data, 13)
	local t1 = d:float(pdu_data, 17)
	local range = d:float(pdu_data, 21)
	local dust_raw = d:float(pdu_data, 25)
	local state = d:float(pdu_data, 29)

	local now = ioe.time()

	local quality = state == 0x0001 and 0 or 1

	local flags = {
		0x0001 = 'N',
		0x0010 = 'M',
		0x0020 = 'C',
		0x0040 = 'M',
		0x0080 = 'D',
	}
	local flag = flags[state] or 'D'

	self._dev:set_input_prop('state', "value", state, now, 0)
	self._dev:set_input_prop('r1', "value", r1, now, 0)
	self._dev:set_input_prop('r2', "value", r2, now, 0)
	self._dev:set_input_prop('k1', "value", k1, now, 0)
	self._dev:set_input_prop('k2', "value", k2, now, 0)
	self._dev:set_input_prop('range', "value", range, now, 0)
	self._dev:set_input_prop('dust_raw', "value", dust_raw, now, 0)

	self:set_input('dust', dust, nil, now, quality, flag)
end

return worker
