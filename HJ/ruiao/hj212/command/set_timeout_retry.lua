local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.set_timeout_retry')

function cmd:initialize(over_time, re_count)
	local over_time = over_time or 5
	local re_count = re_count or 3
	base.initialize(self, types.COMMAND.SET_TIMEOUT_RETRY, {
		Overtime = over_time,
		ReCount = re_count
	})
end

return cmd
