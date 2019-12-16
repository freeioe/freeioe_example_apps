local class = require 'middleclass'

local calc = class("smc.range.conversion")

function calc:initialize(raw_min, raw_max, value_min, value_max)
	assert(raw_min and raw_max and value_min and value_max, "Arguments error!")
	self._raw_min = tonumber(raw_min) or 0
	self._raw_max = tonumber(raw_max) or 0
	self._value_min = tonumber(value_min) or 0
	self._value_max = tonumber(value_max) or 0

	assert(self._raw_min < self._raw_max, "Raw value range error")
	assert(self._value_min < self._value_max, "Raw value range error")
end

function calc:to_value(raw)
	local val = tonumber(raw)
	if val < self._raw_min then
		return nil, "Out range [min]"
	end
	if val > self._raw_max then
		return nil, "Out range [max]"
	end

	return (val - self._raw_min) * (self._value_max - self._value_min) / (self._raw_max - self._raw_min)
end

function calc:to_raw(value)
	local raw = tonumber(value)
	if val < self._value_min then
		return nil, "Out range [min]"
	end
	if val > self._value_max then
		return nil, "Out range [max]"
	end

	return (raw - self._value_min) * (self._raw_max - self._raw_min) / (self._value_max - self._value_min)
end

return  calc
