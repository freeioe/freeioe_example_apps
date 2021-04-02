local base = require 'hj212.client.handler.base'

local handler = base:subclass('hj212.client.handler.set_min_interval')

function handler:process(request)
	local params = request:params()
	local interval, err = params:get('MinInterval')
	interval = tonumber(interval)
	if interval == nil then
		return nil, err
	end

	self:log('info', "Set MIN interval to "..interval)

	local station = self._client:station()
	if not station then
		return nil, "Client has no station??"
	end
	return station:update_min_interval(interval)
end

return handler
