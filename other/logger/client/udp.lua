local skynet = require 'skynet'
local socket = require 'skynet.socket'
local base = require 'client.base'

local client = base:subclass("LOGGER_CLIENT_UDP")

--- 
function client:initialize(logger, fmt, host, port)
	base.initialize(self, logger, fmt)
	self._host = host
	self._port = tonumber(port) or 1514
end

--- Timeout: ms
function client:send(raw_data)
	return socket.write(self._socket, raw_data)
end

function client:start()
	if self._socket then
		return nil, "Already started"
	end

	self._socket = socket.udp(function(str, from)
		print(from, str)
	end, '0.0.0.0', math.random(6100, 6100 + 100))

	socket.udp_connect(self._socket, self._host, self._port)

	return self._socket
end

function client:stop()
	if not self._socket then
		return
	end

	skynet.close(self._socket)
	self._socket = nil
end

return client 
