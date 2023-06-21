local class = require 'middleclass'
local types = require 'iec60870.types'
local helper = require 'iec60870.common.helper'
local logger = require 'iec60870.common.logger'
local ti_map = require 'iec60870.asdu.ti_map'

local parser = class('LUA_IEC60870_FRAME_DATA_PARSER')

function parser:initialize(cb)
	self._cb = assert(cb)
end

local function data_to_string(data)
	local t = {}
	for _, v in ipairs(data) do
		table.insert(t, helper.totable(v))
	end
	local cjson = require 'cjson.safe'
	return cjson.encode(t)
end

local function ti_short_name(ti)
	local name = types.typeid2_table[ti]
	if not name then
		return nil, 'Unknown TI'
	end
	local side, tp, dt, ver = string.match(name, '^(%a)_(%a+)_(%a+)_(%d+)$')
	return assert(tp), assert(dt), tonumber(ver)
end

function parser:__call(obj, asdu)
	local unit = asdu:UNIT()
	local ti, dt, ver = ti_short_name(unit:TI())
	local caoa = unit:CAOA():ADDR()
	local cot = unit:COT():CAUSE()

	local timestamp = obj:TIME() / 1000
	local addr = obj:ADDR():ADDR()
	local data = obj:DATA()
	local iv = obj:IV()

	if ti == 'SP' then
		local val = assert(data[1]:SPI())
		self._cb(caoa, ti, addr, val, timestamp, iv)
	elseif ti == 'DP' then
		local val = assert(data[1]:DPI())
		self._cb(caoa, ti, addr, val, timestamp, iv)
	elseif ti == 'ME' then
		local val = assert(data[1]:VAL())
		self._cb(caoa, ti, addr, val, timestamp, iv)
	elseif ti == 'IT' then
		local val = assert(data[1]:VAL())
		self._cb(caoa, ti, addr, val, timestamp, iv)
	elseif ti == 'ST' then
		local val = assert(data[1]:VAL())
		self._cb(caoa, ti, addr, val, timestamp, iv)
	elseif ti == 'BO' then
		local val = assert(data[1]:VAL(), data[1])
		self._cb(caoa, ti, addr, val, timestamp, iv)
	else
		logger.error('UNKNOWN TI', caoa, types.typeid2_table[unit:TI()], addr, data_to_string(data), timestamp, iv)
		-- self._cb(caoa, addr, data, timestamp, iv)
	end
end

return parser
