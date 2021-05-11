local base = require 'hj212.client.handler.base'

local handler = base:subclass('hj212.client.handler.set_rdata_interval')

function handler:process(request)
	local params = request:params()
	local interval, err = params:get('RtdInterval')
	interval = tonumber(interval)
	if interval == nil then
		return nil, err
	end

	self:log('debug', "Set RData interval to "..interval)

	local station = self._client:station()
	if not station then
		return nil, "Client has no station??"
	end
	return station:update_rdata_interval(interval)
end

return handler
