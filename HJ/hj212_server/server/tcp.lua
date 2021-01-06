local skynet = require 'skynet'
local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local client = require 'server.client.tcp'
local base = require 'server.base'

local server = base:subclass("hj212_sever.server.tcp")

--- 
--
function server:initialize(app, host, port)
	assert(app, "App missing")
	assert(host, "Host missing")
	assert(port, "Port missing")
	base.initialize(self, app)
	self._host = host
	self._port = port
	self._closing = false
	self._clients = {}
end

function server:listen_proc()
	local log = self._app:log_api()

	local sleep_time = 100 -- one second
	while not self._closing do
		if not self._socket then
			skynet.sleep(sleep_time, self)
			local sock, err = self:create_listen()
			if sock then
				self._socket = sock
			else
				sleep_time = sleep_time * 2
				if sleep_time > 64 * 100 then
					sleep_time = 100
				end
				log:error("Wait for retart listenion", sleep_time)
			end
		else
			skynet.sleep(100, self)
		end

		if self._closing then
			break
		end
	end

	assert(self._closing)

	--- Close listening
	if self._socket then
		socket.close(self._socket)
		self._socket = nil
	end

	-- Cleanup clients
	for fd, cli in pairs(self._clients) do
		cli:close()
	end
	self._clients = {}

	-- Wakeup  closing
	skynet.wakeup(self._closing)
end

function server:create_listen()
	local log = self._app:log_api()
	local host = self._host
	local port = self._port
	local nodelay = self._nodelay

	log:notice(string.format("Listen on %s:%d", host, port))
	local sock, err = socket.listen(host, port)
	if not sock then
		return nil, string.format("Cannot listen on %s:%d. err: %s", host, port, err or "")
	end

	socket.start(sock, function(fd, addr)
		log:notice(string.format("New connection come (fd = %d, %s)", fd, addr))
		if nodelay then
			socketdriver.nodelay(fd)
		end

		local host, port = string.match(addr, "^(.+):(%d+)$")

		if self._clients[fd] then
			self._clients[fd]:close()
			self._clients[fd] = nil
		end
		assert(self._clients[fd] == nil)

		local cli = client:new(self, fd, host, port)
		if self:valid_connection(cli) then
			self._clients[fd] = cli
			cli:start()
		else
			cli:close()
		end
	end)
	return sock
end

function server:start()
	if self._socket then
		return nil, "Already started"
	end
	if self._closing then
		return nil, "Server is closing"
	end

	skynet.fork(function()
		self:listen_proc()
	end)

	return true
end

function server:stop()
	if not self._socket then
		return nil, "Already stoped"
	end
	if self._closing then
		return nil, "Server is stoping"
	end

	self._closing = {}
	skynet.wakeup(self)

	for fd, cli in pairs(self._clients) do
		cli:close()
	end
	skynet.wait(self._closing)
	assert(self._socket == nil)
	self._closing = nil
	self._clients = {}

	return base.stop(self)
end

return server 
