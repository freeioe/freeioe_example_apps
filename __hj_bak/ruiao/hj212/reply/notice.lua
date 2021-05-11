local types = require 'hj212.types'
local command = require 'hj212.command.notice'
local base = require 'hj212.reply.base'

local resp = base:subclass('hj212.reply.notice')

function resp:initialize(session)
	local cmd = command:new()
	base.initialize(self, session, cmd)
end

return resp
