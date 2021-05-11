local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.state_stop')

function cmd:initialize()
	base.initialize(self, types.COMMAND.STATE_STOP, {})
end

return cmd
