local date = require 'date'
local base = require 'hj212.server.handler.base'
local types = require 'hj212.types'

local handler = base:subclass('hj212.server.handler.get_time')

function handler:process(request)
	return true
end

return handler
