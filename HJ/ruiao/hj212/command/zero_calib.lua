local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.zero_calib')

function cmd:initialize(pol_id)
	local pol_id = pol_id or 'xxxxx'
	base.initialize(self, types.COMMAND.ZERO_CALIB, {
		PolId = pol_id
	})
end

return cmd
