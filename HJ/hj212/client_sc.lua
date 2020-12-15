local skynet = require 'skynet'
local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local base = require 'hj212.client.base'

local client = base:subclass("HJ212_CLIENT_SC")

--- 
function client:initialize(opt)
	base.initialize(self, opt.system, opt.dev_id, opt.passwd, opt.timeout, opt.retry)
	self._closing = false
	self._opt = opt
	self._requests = {}
	self._results = {}
	self._buf = {}
end

function client:set_dump(cb)
	self._dump = cb
end

function client:dump_raw(io, raw_data)
	if self._dump then
		self._dump(io, raw_data)
	end
end

--- Timeout: ms
function client:send(session, raw_data)
	local t_left = self:timeout()
	while not self._socket and t_left > 0 do
		skynet.sleep(100)
		t_left = t_left - 1000
		if self._closing then
			return nil, "Connection closing!!!"
		end
	end
	if t_left <= 0 then
		return nil, "Not connected!!"
	end

	self:dump_raw('OUT', raw_data)

	--local basexx = require 'basexx'
	--print(os.date(), 'Send request', session)
	--print(os.date(), 'OUT:', basexx.to_hex(raw_data))

	local t = {}
	self._requests[session] = t

	local cur = 0
	while cur < self:retry() do
		local r, err = socket.write(self._socket, raw_data)
		if not r then
			self._requests[session] = nil
			return nil, err
		end
		skynet.sleep(timeout / 10, t)
		if self._results[session] then
			break
		end
		cur = cur + 1
	end

	local result = self._results[session] or {false, "Timeout"}
	self._results[session] = nil
	if not result[1] then
		--print(os.date(), 'Request failed', session, table.unpack(result))
	else
		--print(os.date(), 'Request done', session)
	end
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
		skynet.error("Wait for retart connection", connect_gap)
	end

	if self._socket then
		self:watch_client_socket()
	end
end

function client:watch_client_socket()
	while self._socket and not self._closing do
		local data, err = socket.read(self._socket)	
		if not data then
			skynet.error("Socket disconnected", err)
			break
		end
		self:on_recv(data)
	end

	if self._socket then
		local to_close = self._socket
		self._socket = nil
		socket.close(to_close)
	end

	if self._closing then
		return
	end

	--- reconnection
	skynet.timeout(100, function()
		self:connect_proc()
	end)
end

function client:start_connect()
	local host = self._opt.host
	local port = self._opt.port
	skynet.error(string.format("Connecting to %s:%d", host, port))
	local sock, err = socket.open(host, port)
	if not sock then
		local err = string.format("Cannot connect to %s:%d. err: %s",
		host, port, err or "")
		skynet.error(err)
		return nil, err
	end
	skynet.error(string.format("Connected to %s:%d", host, port))

	if self._opt.nodelay then
		socketdriver.nodelay(sock)
	end

	self._socket = sock
	return true
end

function client:on_recv(data)
	--local basexx = require 'basexx'
	--print(os.date(), 'IN:', basexx.to_hex(data))
	table.insert(self._buf, data)
	if self._buf_wait then
		skynet.wakeup(self._buf_wait)
	end

	if self._io_cb then
		self._io_cb('IN', data)
	end
end

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
			if #self._buf > 0 then
				local data = table.concat(self._buf)
				self._buf = {}

				local p, reply = protect_call(self, 'process', data)
				if p then
					local session = p:session()
					local req_co = self._requests[session]
					if req_co then
						self._results[session] = {p}
						skynet.wakeup(req_co)
					else
						self:on_request(p)
					end
				else
					if self._log then
						self._log:debug(reply)
					end
				end
			end

			self._buf_wait = {}
			skynet.sleep(1000, self._buf_wait)
			self._buf_wait = nil
		end
	end)
	return true
end

function client:close()
	self._closing = true
	if self._buf_wait then
		skynet.wakeup(self._buf_wait) -- wakeup the process co
	end
	if self._connection_wait then
		skynet.wakeup(self._connection_wait) -- wakeup the process co
	end
	for k, v in pairs(self._requests) do
		skynet.wakeup(v)
	end
	self._requests = {}
	self._results = {}
end

return client 
