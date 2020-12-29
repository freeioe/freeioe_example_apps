local base = require 'calc.base'
local air_helper = require 'hj212.calc.air_helper'

local calc = base:subclass('HJ212_CALC_AIR_QSNH')

-- value: Qs
function calc:calc(value)
	local cems = self:station():cems()
	assert(cems)
	return air_helper.Qsn(value, cems:ts(), cems:Ba(), cems:Ps(), cems:Xsw() / 100)
end

return calc
