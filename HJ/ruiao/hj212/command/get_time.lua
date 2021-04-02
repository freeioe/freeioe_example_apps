local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.get_time')

function cmd:initialize(pol_id, system_time)
	local pol_id = pol_id or 'xxxxx'
	local system_time = system_time  -- optional
	base.initialize(self, types.COMMAND.GET_TIME, {
		PolId = pol_id,
		SystemTime = system_time
	})
end

return cmd
