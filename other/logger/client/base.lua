local class = require 'middleclass'

local base = class('freeioe.logger.client.base')

function base:initialize(logger, format)
	assert(format)
	self._logger = logger
	self._format = format
end

function base:publish_log(...)
	return self:send(self._format.log(...))
end

function base:publish_comm(...)
	return self:send(self._format.comm(...))
end

function base:send(data)
	assert(nil, "Send not implemented")
end

function base:start()
	return true
end

function base:stop()
	return true
end

return base
