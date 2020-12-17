local base = require 'calc.base'
local air_helper = require 'hj212.calc.air_helper'

local calc = base:subclass('HJ212_CALC_AIR_QSH')

-- value: Vsh
function calc:calc(value)
	local cems = self:station():cems()
	assert(cems)
	return air_helper.Qsh(cmes:F(), value)
end

return calc
