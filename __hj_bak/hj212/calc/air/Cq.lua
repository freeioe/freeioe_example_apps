local base = require 'calc.base'
local air_helper = require 'hj212.calc.air_helper'

local calc = base:subclass('HJ212_CALC_AIR_CQ')

function calc:calc(value)
	local g_mol = tonumber(self:param())
	assert(g_mol)
	return air_helper.Cq(value, g_mol)
end

return calc
