local base = require 'hj212.client.handler.base'

local handler = base:subclass('hj212.client.handler.rdata_start')

function handler:process(request)
	self:log('info', "Disable RData upload!")

	self._client:set_rdata_enable(false)
	return true
end

return handler
