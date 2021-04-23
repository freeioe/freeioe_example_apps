local skynet = require 'skynet'
local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local base = require 'hj212.client.base'
local types = require 'hj212.types'

local client = base:subclass("HJ212_CLIENT_SC")

local function protect_call(obj, func, ...)
	assert(obj and func)
	local f = obj[func]
	if not f then
		return nil, "Object has no function "..func
	end

	local ret = {xpcall(f, debug.traceback, obj, ...)}
	if not ret[1] then
		return nil, table.concat(ret, '', 2)
	end
	return table.unpack(ret, 2)
end

--- 
function client:initialize(station, opt, conn)
	assert(station and opt)
	local ver = types.PROTOCOL.V2017
	if opt.version then
		ver = assert(types.PROTOCOL['V'..opt.version])
	end
	base.initialize(self, station, opt.passwd, opt.timeout, opt.retry, {ver=ver})
	self._conn = conn
	self._name = opt.name
	self._closing = false
	self._opt = opt
	self._requests = {}
	self._results = {}
	self._buf = {}
	self:add_handler('handler')
end

function client:set_connection_cb(cb)
	self._connection_cb = cb
end

function client:log(level, fmt, ...)
	return base.log(self, level, '['..self._name..']'..fmt, ...)
end

function client:set_dump(cb)
	self._dump = cb
end

function client:dump_raw(io, raw_data)
	if self._dump then
		self._dump(io, raw_data)
	end
end

function client:set_retry_cb(cb)
	self._retry_cb = cb
end

function client:is_connected()
	return self._socket ~= nil
end

--- Timeout: ms
function client:send(session, raw_data)
	local timeout = self:timeout()
	local t_left = timeout * 3
	while not self._socket and t_left > 0 do
		if self._closing then
			return nil, "Connection closing!!!"
		end
		skynet.sleep(100)
		t_left = t_left - 1000
	end
	if t_left <= 0 then
		return nil, "Not connected!!"
	end

	--local basexx = require 'basexx'
	--self:log('debug', 'Send request', session)
	--self:log('debug', 'OUT:', basexx.to_hex(raw_data))

	if self._requests[session] then
		self:log('trace', 'Wait for same session finished', session)
		while self._requests[session] and self._socket and not self._closing do
			skynet.sleep(10)
			t_left = t_left - 100
		end
		self:log('trace', 'Wait for same session done', session)
		if not self._socket or self._closing  then
			return nil, "Socket closed"
		end
	end

	local t = {}
	self._requests[session] = t

	local cur = 0
	while cur < self:retry() and self._socket do
		if cur ~= 0 then
			self:log('warning', 'Resend request', session, cur)
			if self._retry_cb then
				self._retry_cb(self._name, cur, self:retry(), raw_data)
			end
		end
		self:log('trace', "Send request", session)
		local r, err = socket.write(self._socket, raw_data)
		if not r then
			self._results[session] = {false, err or 'Disconnected'}
			break
		end
		self:dump_raw('OUT', raw_data)
		skynet.sleep(timeout / 10, t)
		if self._results[session] then
			break
		end
		cur = cur + 1
	end

	local result = self._results[session] or {false, "Timeout"}

	-- Cleanup
	self._requests[session] = nil
	if not self._results[session] then
		if self._socket and self:retry() > 1 then
			self:log('error', 'Request failed after retried, close the current connection')
			socket.close(self._socket)
			self._socket = nil
		end
	else
		self._results[session] = nil
	end


	--[[
	if not result[1] then
		self:log('debug', 'Request failed', session, table.unpack(result))
	else
		self:log('debug', 'Request done', session)
	end
	]]--
	return table.unpack(result)
end

function client:send_nowait(raw_data)
	if not self._socket then
		return nil, "Socket not connected"
	end

	self:dump_raw('OUT', raw_data)

	return socket.write(self._socket, raw_data)
end

function client:connect_proc()
	self._buf = {} --- Cleanup buffer data
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
		self:log('info', "Wait for restart connection", connect_gap)
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
			self:log('error', "Socket disconnected", err)
			break
		end
		self:on_recv(data)
	end

	if self._connection_cb then
		self._connection_cb(false)
	end

	for k, v in pairs(self._requests) do
		skynet.wakeup(v)
	end
	skynet.sleep(10)
	self._requests = {}
	self._results = {}

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
	local host = self._opt.host
	local port = self._opt.port
	self:log('info', string.format("Connecting to %s:%d", host, port))
	local sock, err = socket.open(host, port)
	if not sock then
		local err = string.format("Cannot connect to %s:%d. err: %s",
									host, port, err or "")
		self:log('error', err)
		return nil, err
	end
	self:log('info', string.format("Connected to %s:%d", host, port))

	if self._opt.nodelay then
		socketdriver.nodelay(sock)
	end

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

function client:connect()
	if self._socket or self._port then
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
				self:log('error', err)
			end
		end
		self:log('info', 'Client workproc quited', self._closing and 'closing' or 'exception')
	end)
	return true
end

function client:process_socket_data()
	while not self._closing do
		if #self._buf > 0 then
			local data = table.concat(self._buf)
			self._buf = {}

			local p, reply, left = self:process(data)
			if p then
				local session = p:session()
				if reply then
					local req_co = self._requests[session]
					if req_co then
						self:log('debug', "Received response", session)
						self._results[session] = {p}
						skynet.wakeup(req_co)
					else
						self:log('error', "Missing request on session:"..session)
					end
				else
					-- Create coroutine for request handle
					skynet.fork(function()
						self:on_request(p)
					end)
				end
			end
			if left and string.len(left) > 0 then
				table.insert(self._buf, 1, left)
				if p then
					-- Continue to process
					skynet.sleep(1)
				else
					--- Wait for data
					self._buf_wait = {}
					skynet.sleep(1000, self._buf_wait)
					self._buf_wait = nil
				end
			end
		else
			self._buf_wait = {}
			skynet.sleep(1000, self._buf_wait)
			self._buf_wait = nil
		end
	end
end

function client:close()
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

function client:on_command_min_data(stime, etime)
	local data = self._station:min_data(stime, etime)
	return self._conn:upload_min_data(data)
end

function client:on_command_hour_data(stime, etime)
	local data = self._station:hour_data(stime, etime)
	return self._conn:upload_hour_data(data)
end

function client:on_command_day_data(stime, etime)
	local data = self._station:hour_data(stime, etime)
	return self._conn:upload_hour_data(data)
end

function client:on_gate_add_person(info, SFP)
	if SFP == 1 then
		return self._conn:send_command('STATION.GATE', 'add_person', info)
	else
		return self._conn:send_command('STATION.GATE', 'del_person', info)
	end
end

function client:on_gate_open(info)
	return self._conn:send_command('STATION.GATE', 'open_gate', info)
end

return client 
