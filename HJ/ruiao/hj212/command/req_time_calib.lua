local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.req_time_calib')

function cmd:initialize(pol_id)
	local pol_id = pol_id or 'xxxxx'
	base.initialize(self, types.COMMAND.REQ_TIME_CALIB, {
		PolId = pol_id,
	})
end

return cmd
