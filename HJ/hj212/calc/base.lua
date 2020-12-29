local class = require 'middleclass'

local base = class('HJ212_CALC_BASE')

function base:initialize(station, next_calc, param)
	self._station = station
	self._next = next_calc
	self._param = param
end

function base:station()
	return self._station
end

function base:next()
	return self._next
end

function base:param()
	return self._param
end

function base:__call(value, timestamp)
	if self._next then
		return self._next(self:calc(value, timestamp))
	end
	return self:calc(value, timestamp)
end

function base:calc(value, timestamp)
	assert(nil, "Not implemented")
end

return base
