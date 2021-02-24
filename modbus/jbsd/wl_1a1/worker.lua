local class = require 'middleclass'
local pdu = require 'modbus.pdu.init'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'
local bcd = require 'bcd'

local worker = class("WL_1A1.worker")

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

function worker:run(modbus)
	if self._conf.fm_type == 'NEWER_15_01' then
		return self:run_03(modbus, true)
	else
		return self:run_04(modbus)
	end
end

function worker:run_03(modbus, not_reading_bcd)
	local func = 0x03
	local req, err = self._pdu:make_request(func, 0, 16)
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
		self._log:warning("read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1)))
		return
	end

	local len = d:uint8(pdu, 2)
	assert(len >= 16 * 2, SF("length issue :%d - %d", len, 16 * 2))

	local pdu_data = string.sub(pdu, 3)
	local flow = d:float(pdu_data, 1)
	local flow_2 = d:float(pdu_data, 5)
	local flow_cou = d:float(pdu_data, 9)
	local liquid_level = d:float(pdu_data, 13)
	local I1 = d:float(pdu_data, 17)
	local I2 = d:float(pdu_data, 21)
	local I3 = d:float(pdu_data, 25)
	local I4 = d:float(pdu_data, 29)
	--local flow_cou = base64.from_hex(string.sub(33, 36))

	self._dev:set_input_prop('flow', "value", flow)
	self._dev:set_input_prop('flow_2', "value", flow_2)
	if not_reading_bcd then
		self._dev:set_input_prop('flow_cou', "value", flow_cou)
	end
	self._dev:set_input_prop('liquid_level', "value", liquid_level)
	self._dev:set_input_prop('I1', "value", I1)
	self._dev:set_input_prop('I2', "value", I2)
	self._dev:set_input_prop('I3', "value", I3)
	self._dev:set_input_prop('I4', "value", I4)

	if not not_reading_bcd then
		local func = 0x03
		local req, err = self._pdu:make_request(func, 16, 2)
		if not req then
			self._log:error("make request failed: "..err)
			return nil, err
		end
		local pdu, err = modbus:request(self._unit, req, 1000)
		if not pdu then
			self._log:error("Request failed: "..err)
			return nil, err
		end

		--- 解析数据
		local d = self._data_unpack
		if d:uint8(pdu, 1) == (0x80 + func) then
			local basexx = require 'basexx'
			self._log:warning("read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1)))
			return
		end

		local len = d:uint8(pdu, 2)
		assert(len >= 2 * 2)

		local pdu_data = string.sub(pdu, 3)
		local flow_cou = bcd.decode(pdu_data)
		self._dev:set_input_prop('flow_cou', "value", flow_cou)
	end
end

function worker:run_04(modbus)
	local func = 0x04
	local req, err = self._pdu:make_request(func, 0, 9)
	if not req then
		self._log:error("make request failed: "..err)
		return nil, err
	end
	local pdu, err = modbus:request(self._unit, req, 1000)
	if not pdu then
		self._log:error("Request failed: "..err)
		return nil, err
	end

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		self._log:warning("read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1)))
		return
	end

	local len = d:uint8(pdu, 2)
	assert(len >= 9 * 2, SF("length issue :%d - %d", len, 9 * 2))

	local pdu_data = string.sub(pdu, 3)
	local f = d:uint16(pdu_data, 1)
	local flow_2 = self._conf.mr_flow * (f / 0xFFFF) 
	local flow = (flow_2 * 1000) / 3600

	local flow_cou = d:uint32(pdu_data, 5)

	f = d:int16(pdu_data, 9)
	local liquid_level = self._conf.mr_liquid_level * (f / 0xFFFF)

	f = d:int16(pdu_data, 11)
	local I1 = self._conf.mr_I1 * (f / 0xFFFF)

	f = d:int16(pdu_data, 13)
	local I2 = self._conf.mr_I2 * (f / 0xFFFF)

	f = d:int16(pdu_data, 15)
	local I3 = self._conf.mr_I3 * (f / 0xFFFF)

	f = d:int16(pdu_data, 17)
	local I4 = self._conf.mr_I4 * (f / 0xFFFF)

	self._dev:set_input_prop('flow', "value", flow)
	self._dev:set_input_prop('flow_2', "value", flow_2)
	self._dev:set_input_prop('flow_cou', "value", flow_cou)
	self._dev:set_input_prop('liquid_level', "value", liquid_level)
	self._dev:set_input_prop('I1', "value", I1)
	self._dev:set_input_prop('I2', "value", I2)
	self._dev:set_input_prop('I3', "value", I3)
	self._dev:set_input_prop('I4', "value", I4)
end

return worker
