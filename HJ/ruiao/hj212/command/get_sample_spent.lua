local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.get_sample_spent')

function cmd:initialize(pol_id, s_time)
	local pol_id = pol_id or 'xxxxx'
	local s_time = s_time or 40
	base.initialize(self, types.COMMAND.GET_SAMPLE_SPENT, {
		PolId = pol_id,
		Stime = s_time,
	})
end

return cmd
