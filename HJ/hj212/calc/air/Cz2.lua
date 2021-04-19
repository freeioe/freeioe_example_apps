local base = require 'calc.base'
local air_helper = require 'hj212.calc.air_helper'

local calc = base:subclass('HJ212_CALC_AIR_DRYC')

function calc:calc(value)
	local cems = self:station():cems()
	assert(cems)
	local Co2s = tonumber(self:param() or cems:Co2s())
	assert(Co2s)
	return air_helper.Cz2(value, cems:Cvo2(), Co2s) 
end

return calc
