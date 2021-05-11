local base = require 'hj212.command.base'
local types = require 'hj212.types'

local reply = base:subclass('hj212.command.notice')

function reply:initialize()
	base.initialize(self, types.COMMAND.NOTICE, {})
end

return reply
