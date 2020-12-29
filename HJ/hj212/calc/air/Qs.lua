local base = require 'calc.base'
local air_helper = require 'hj212.calc.air_helper'

local calc = base:subclass('HJ212_CALC_AIR_QSH')

-- value: Vs
function calc:calc(value)
	local cems = self:station():cems()
	assert(cems)
	return air_helper.Qs(cmes:F(), value)
end

return calc
