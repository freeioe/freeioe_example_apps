local base = require 'hj212.command.base'
local types = require 'hj212.types'

local reply = base:subclass('hj212.command.reply')

function reply:initialize(result)
	local result = result ~= nil and result or types.REPLY.RUN
	base.initialize(self, types.COMMAND.REPLY, {
		QnRtn = result
	})
end

return reply
