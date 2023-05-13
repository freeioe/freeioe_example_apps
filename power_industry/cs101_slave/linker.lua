local base = require 'iec60870.common.linker'
local skynet = require 'skynet'
local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local serial = require 'serialdriver'

local linker = base:subclass("LUA_APP_LINKER_CLASS")

--- 
-- linker_type: tcp/serial
function linker:initialize(opt, log)
	base.initialize(self)

	-- Set default link to serial
	opt.link = string.lower(opt.link or 'serial')

	self._closing = false
	self._opt = opt
	self._log = log
end

function linker:send(raw)
	return self:write(raw, 1000)
end

--- Timeout: ms
function linker:write(raw, timeout)
	assert(raw, 'Send linker is nil')
	assert(timeout, 'Send timeout is nil')
	if self._closing then
		return nil, "Connection closing!!!"
	end

	local t_left = timeout
	while not self._socket and not self._port and t_left > 0 do
		skynet.sleep(100)
		t_left = t_left - 1000
		if self._closing then
			return nil, "Connection closing!!!"
		end
	end
	if t_left <= 0 then
		self._log:debug('Wait for connection timeout', timeout)
		return nil, "Not connected!!"
	end

	--[[
	if self._handler then
		self._handler.on_send(raw)
	end
	]]--

	if self._socket then
		return socket.write(self._socket, raw)
	end
	if self._port then
		return self._port:write(raw)
	end
	return nil, "Connection closed!!!"
end

function linker:connect_proc()
	local connect_gap = 100 -- one second
	self._log:debug("connection proc enter...")
	while not self._closing do
		self._connection_wait = {}
		self._log:debug("connection sleep", connect_gap)
		skynet.sleep(connect_gap, self._connection_wait)
		self._connection_wait = nil
		if self._closing then
			break
		end

		local r, err = self:start_connect()
		if r then
			self._log:error("Start connection failed", err)
			break
		end

		connect_gap = connect_gap * 2
		if connect_gap > 64 * 100 then
			connect_gap = 100
		end
		self._log:error("Wait for retart connection", connect_gap)
	end

	if self._server_socket then
		self:watch_server_socket()
	end
	self._log:debug("connection proc exit...")
end

function linker:watch_server_socket()
	while self._server_socket do
		while self._server_socket and not self._socket do
			skynet.sleep(10)
		end
		if not self._server_socket then
			break
		end

		while self._socket and self._server_socket do
			local data, err = socket.read(self._socket)	
			if not data then
				skynet.error("Client socket disconnected", err)
				break
			end
			self:on_recv(data)
		end

		if self._socket then
			local to_close = self._socket
			self._socket = nil
			socket.close(to_close)
			self:on_disconnected()
		end
	end

	if not self._server_socket then
		skynet.timeout(100, function()
			self:connect_proc()
		end)
	end
end

function linker:start_connect()
	if self._opt.link == 'tcp' then
		local conf = self._opt.tcp
		self._log:info(string.format("Listen on %s:%d", conf.host, conf.port))
		local sock, err = socket.listen(conf.host, conf.port)
		if not sock then
			local err = string.format("Cannot listen on %s:%d. err: %s", conf.host, conf.port, err or "")
			self._log:error(err)
			return nil, err
		end
		self._server_socket = sock
		socket.start(sock, function(fd, addr)
			skynet.error(string.format("New connection (fd = %d, %s)",fd, addr))
			--- TODO: Limit client ip/host

			if conf.nodelay then
				socketdriver.nodelay(fd)
			end

			local to_close = self._socket
			socket.start(fd)
			self._socket = fd

			local host, port = string.match(addr, "^(.+):(%d+)$")
			if host and port then
				self._socket_peer = cjson.encode({
					host = host,
					port = port,
				})
			else
				self._socket_peer = addr
			end
			if to_close then
				skynet.error(string.format("Previous socket closing, fd = %d", to_close))
				socket.close(to_close)
				self:on_disconnected()
			end

			self:on_connected()
		end)
		return true
	end
	if self._opt.link == 'serial' then
		local opt = self._opt.serial
		local port = serial:new(opt.port, opt.baudrate or 9600, opt.data_bits or 8, opt.parity or 'NONE', opt.stop_bits or 1, opt.flow_control or "OFF")
		self._log:info("Open serial port:"..opt.port)
		local r, err = port:open()
		if not r then
			self._log:error("Failed open serial port:"..opt.port..", error: "..err)
			return nil, err
		end

		port:start(function(data, err)
			-- Recevied Data here
			if data then
				self:on_recv(data)
			else
				self._log:error(err)
				port:close()
				self._port = nil
				skynet.timeout(100, function()
					self:connect_proc()
				end)
				self:on_disconnected()
			end
		end)

		self._port = port
		self:on_connected()
		return true
	end
	return false, "Unknown Link Type"
end

function linker:open()
	self._log:debug("Linker open...")
	if self._socket or self._port then
		return nil, "Already started"
	end

	self._closing = false

	skynet.timeout(100, function()
		self:connect_proc()
	end)

	return true
end

function linker:close()
	self._closing = true
	if self._connection_wait then
		skynet.wakeup(self._connection_wait) -- wakeup the process co
	end
end

function linker:dump_key()
	if self._opt.link == 'tcp' then
		local conf = self._opt.tcp
		return string.format("%s:%d", conf.host, conf.port)
	end

	if self._opt.link == 'serial' then
		local opt = self._opt.serial
		return tostring(opt.port)
	end

	return 'UNKNOWN'
end

return linker 
