local command = require 'hj212.command.uptime'
local base = require 'hj212.request.base'

local req = base:subclass('hj212.request.uptime')

function req:initialize(data_time, restart_time, need_ack)
	local need_ack = need_ack == nil and true or need_ack
	local cmd = command:new(data_time, restart_time)
	base.initialize(self, cmd, need_ack)
end

return req
