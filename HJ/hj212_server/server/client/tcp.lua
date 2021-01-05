local skynet = require 'skynet'
local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local base = require 'server.client.base'

local client = base:subclass("hj212_server.server.client.tcp")

--- 
-- stream_type: tcp/serial
function client:initialize(server, sock, host, port)
	base.initialize(self, server)
	self._socket = sock
	self._host = host
	self._port = port
	self._closing = nil
	self._requests = {}
	self._results = {}
	self._buf = {}
end

function client:host()
	return self._host
end

function client:port()
	return self._port
end

function client:watch_socket()
	-- Register socket
	local sock = self._socket
	socket.start(sock)

	while not self._closing do
		local data, err = socket.read(sock)	
		if not data then
			self:on_disconnect()
			skynet.error("Client socket disclientected", err)
			break
		end
		self:on_recv(data)
	end

	if self._closing then
		if self._buf_wait then
			skynet.wakeup(self._buf_wait)
			skynet.sleep(10) -- Let the buf_wait been closed
		end
		socket.close(self._socket)
		self._socket = nil

		--- completed the session requests
		for session, co in pairs(self._requests) do
			skynet.wakeup(co)
		end
		skynet.sleep(10) -- Let the request been terminated

		--- Wake up closing coroutine
		skynet.wakeup(self._closing)
	end
end

function client:on_recv(data)
	self:dump_raw('IN', data)
	table.insert(self._buf, data)

	if self._buf_wait then
		skynet.wakeup(self._buf_wait)
	end
end

function client:send(session, raw_data, timeout)
	if not self._socket then
		return nil, "No socket connection"
	end
	local timeout = self:timeout()

	local t = {}
	self._requests[session] = t

	local cur = 0
	while not self._closing and cur < self:retry() do
		local sock = self._socket
		if not sock then
			self._results[session] = {false, "Socket closed"}
			break
		end

		if cur ~= 0 then
			self:log('warning', 'Resend request', session, cur)
		end

		local r, err = socket.write(sock, raw_data)
		if not r then
			self._results[session] = {false, err}
			break
		end

		self:dump_raw('OUT', raw_data)

		-- Wait for response
		skynet.sleep(timeout / 10, t)
		if self._results[session] then
			break
		end

		cur = cur + 1
	end

	local result = self._results[session] or {false, "Timeout"}
	self._results[session] = nil
	self._requests[session] = nil

	return table.unpack(result)
end

function client:send_nowait(raw_data)
	if not self._socket then
		return nil, "No socket connection"
	end

	self:dump_raw('OUT', raw_data)

	return socket.write(self._socket, raw_data)
end

function client:start()
	skynet.fork(function()
		self:work_proc()
	end)

	skynet.fork(function()
		self:watch_socket()
	end)
	return true
end

function client:close()
	if not self._socket then
		return nil, "Already closed"
	end
	if self._closing then
		return nil, "Client is closing"
	end

	self._closing = {}
	skynet.wait(self._closing)
	assert(self._socket == nil)
	self._closing = nil

	return true
end

function client:work_proc()
	while not self._closing and self._socket do
		local r, err = xpcall(self.process_socket_data, debug.traceback, self)
		if not r then
			self:log('error', err)
		end
	end
	self:log('info', "Client workproc quited")
end

function client:process_socket_data()
	while not self._closing and self._socket do
		if #self._buf == 0 then
			self._buf_wait = {}
			skynet.sleep(1000, self._buf_wait)
			self._buf_wait = nil
		else
			local data = table.concat(self._buf)
			self._buf = {}

			local p, reply = self:process(data)
			if p then
				local session = p:session()
				if reply then
					local req_co = self._requests[session]
					if req_co then
						self._results[session] = {p}
						skynet.wakeup(req_co)
					else
						self:log('error', "Missing request on session:"..session)
					end
				else
					self:on_request(p)
				end
			end
		end
	end
end

return client 
