local base = require 'hj212.client.handler.base'
local command = require 'hj212.command.get_rdata_interval'
local reply = require 'hj212.reply.base'

local handler = base:subclass('hj212.client.handler.get_rdata_interval')

function handler:process(request)
	self:log('debug', "Get RData interval")

	local station = self._client:station()
	if not station then
		return nil, "Client has no station??"
	end

	local interval = station:rdata_interval()
	local resp = reply:new(request:session(), command:new(interval))
	return self:send_reply(resp)
end

return handler
