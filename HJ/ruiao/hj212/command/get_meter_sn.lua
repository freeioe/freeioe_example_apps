local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.get_meter_sn')

function cmd:initialize(pol_id, sn)
	local pol_id = pol_id or 'xxxxx'
	local s_time = sn or 'xxxxx-SN'
	base.initialize(self, types.COMMAND.GET_METER_SN, {
		PolId = pol_id,
		-- xxxxxx-SN
	})
end

return cmd
