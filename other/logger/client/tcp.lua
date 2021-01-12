local skynet = require 'skynet'
local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local base = require 'client.base'

local client = base:subclass("LOGGER_CLIENT_TCP")

--- 
function client:initialize(logger, fmt, host, port)
	base.initialize(self, logger, fmt)
	self._host = host
	self._port = port
	self._buf = {}
end

function client:set_connection_cb(cb)
	self._connection_cb = cb
end

--- Timeout: ms
function client:send(raw_data)
	local timeout = 5
	local t_left = timeout * 3
	while not self._socket and t_left > 0 do
		if self._closing then
			self._logger:error("Connection closed")
			return nil, "Connection closing!!!"
		end
		skynet.sleep(100)
		t_left = t_left - 1000
	end
	if t_left <= 0 then
		return nil, "Not connected!!"
	end
	
	local data = tostring(string.len(raw_data) + 1)..' '..raw_data..'\n'
	return socket.write(self._socket, data)
	--return socket.write(self._socket, raw_data..'\n')
end

function client:connect_proc()
	local connect_gap = 100 -- one second
	while not self._closing do
		self._connection_wait = {}
		skynet.sleep(connect_gap, self._connection_wait)
		self._connection_wait = nil
		if self._closing then
			break
		end

		local r, err = self:start_connect()
		if r then
			break
		end

		connect_gap = connect_gap * 2
		if connect_gap > 64 * 100 then
			connect_gap = 100
		end
		self._logger:info("Wait for retart connection", connect_gap)
	end

	if self._socket then
		if self._connection_cb then
			self._connection_cb(true)
		end
		self:watch_client_socket()
	end
	if self._closing then
		skynet.wakeup(self._closing)
	end
end

function client:watch_client_socket()
	while self._socket and not self._closing do
		local data, err = socket.read(self._socket)	
		if not data then
			self._logger:error("Socket disconnected", err)
			break
		end
		self:on_recv(data)
	end

	self._logger:error("Connection closing")

	if self._connection_cb then
		self._connection_cb(false)
	end

	skynet.sleep(10)

	if self._socket then
		socket.close(self._socket)
		self._socket = nil
	end

	if not self._closing then
		--- reconnection
		skynet.timeout(100, function()
			self:connect_proc()
		end)
	else
		skynet.wakeup(self._closing)
	end
end

function client:start_connect()
	local host = self._host
	local port = self._port
	self._logger:info(string.format("Connecting to %s:%d", host, port))
	local sock, err = socket.open(host, port)
	if not sock then
		local err = string.format("Cannot connect to %s:%d. err: %s", host, port, err or "")
		self._logger:error(err)
		return nil, err
	end
	self._logger:info(string.format("Connected to %s:%d", host, port))

	socketdriver.nodelay(sock)

	self._socket = sock
	return true
end

function client:on_recv(data)
	self:dump_raw('IN', data)
	table.insert(self._buf, data)

	if self._buf_wait then
		skynet.wakeup(self._buf_wait)
	end
end

function client:start()
	if self._socket then
		return nil, "Already started"
	end

	self._closing = false

	skynet.timeout(100, function()
		self:connect_proc()
	end)

	skynet.fork(function()
		while not self._closing do
			local r, err = xpcall(self.process_socket_data, debug.traceback, self)
			if not r then
				self._logger:error(err)
			end
		end
		self._logger:info('Client workproc quited', self._closing and 'closing' or 'exception')
	end)
	return true
end

function client:process_socket_data()
	while not self._closing do
		if #self._buf > 0 then
			local data = table.concat(self._buf)
			self._buf = {}

			print(data)
		else
			self._buf_wait = {}
			skynet.sleep(1000, self._buf_wait)
			self._buf_wait = nil
		end
	end
end

function client:stop()
	if self._closing then
		return nil, "Closing"
	end

	self._closing = {}

	if self._buf_wait then
		skynet.wakeup(self._buf_wait) -- wakeup the process co
	end
	if self._connection_wait then
		skynet.wakeup(self._connection_wait) -- wakeup the process co
	end
	if self._socket then
		local to_close = self._socket
		self._socket = nil
		socket.close(to_close)
	end

	skynet.wait(self._closing)
	skynet.sleep(100)
	self._closing = nil
end

return client 
