local types = require 'hj212.types'
local command = require 'hj212.command.result'
local base = require 'hj212.reply.base'

local resp = base:subclass('hj212.reply.result')

function resp:initialize(session, result_status)
	local cmd = command:new(result_status)
	base.initialize(self, session, cmd)
end

return resp
