local base = require 'hj212.command.base'
local types = require 'hj212.types'

local reply = base:subclass('hj212.command.data_ack')

function reply:initialize()
	base.initialize(self, types.COMMAND.DATA_ACK, {})
end

return reply
