local base = require 'calc.base'
local air_helper = require 'hj212.calc.air_helper'

local calc = base:subclass('HJ212_CALC_AIR_DRYC')

function calc:calc(value)
	local cems = self:station():cems()
	assert(cems)
	local As = tonumber(self:param() or cems:As())
	assert(As)
	return air_helper.Cz(value, cems:Cvo2(), As) 
end

return calc
