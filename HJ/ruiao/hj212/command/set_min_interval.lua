local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.set_min_interval')

function cmd:initialize(interval)
	local interval = interval or 30
	base.initialize(self, types.COMMAND.SET_MIN_INTERVAL, {
		MinInterval = interval
	})
end

return cmd
