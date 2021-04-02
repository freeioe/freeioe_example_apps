local class = require 'middleclass'

local handler = class('hj212.server.handler.base')

function handler:initialize(client)
	self._client = client
	self._station = client:station()
end

function handler:log(level, ...)
	return self._client:log(level, ...)
end

function handler:__call(...)
	if self.process then
		return self:process(...)
	else
		return nil, "not implemented"
	end
end

function handler:send_request(resp, response)
	return self._client:request(resp, response)
end

function handler:send_reply(resp)
	return self._client:reply(resp)
end

return handler
