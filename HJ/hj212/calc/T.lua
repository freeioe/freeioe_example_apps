local base = require 'calc.base'
local air_helper = require 'hj212.calc.air_helper'

local calc = base:subclass('HJ212_CALC_T')

function calc:initialize(...)
	base.initialize(self, ...)
	self._last = os.time() - 5
end

function calc:calc(value, timestamp)
	local t = self:param()
	if t then
		return value * t
	else
		value = value * (timestamp - self._last)
		self._last = timestamp
		return value
	end
end

return calc
