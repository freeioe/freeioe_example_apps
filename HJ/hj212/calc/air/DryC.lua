local base = require 'calc.base'
local air_helper = require 'hj212.calc.air_helper'

local calc = base:subclass('HJ212_CALC_AIR_DRYC')

function calc:calc(value)
	local cems = self:station():cems()
	assert(cems)
	return air_helper.Csn(value, cems:Xsw()) 
end

return calc
