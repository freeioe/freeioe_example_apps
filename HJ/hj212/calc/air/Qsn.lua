local base = require 'calc.base'
local air_helper = require 'hj212.calc.air_helper'

local calc = base:subclass('HJ212_CALC_AIR_QSNH')

-- value: Qs
function calc:calc(value)
	local cems = self:station():cems()
	assert(cems)
	return air_helper.Qsn(value, cmes:ts(), cmes:Ba(), cmes:Ps(), cmes:Xsw())
end

return calc
