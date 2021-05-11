local base = require 'hj212.server.handler.base'

local handler = base:subclass('hj212.server.handler.day_data')

function handler:process(request)
	return true
end

return handler
