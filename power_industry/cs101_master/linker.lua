local base = require 'iec60870.master.linker'
local skynet = require 'skynet'
local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local serial = require 'serialdriver'

local linker = base:subclass('LUA_APP_STREAM_CLASS')

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

	if self._socket then
		self:watch_client_socket()
	end
	self._log:debug("connection proc exit...")
end

function linker:watch_client_socket()
	while self._socket and not self._closing do
		local data, err = socket.read(self._socket)	
		if not data then
			self._log:error("Socket disconnected", err)
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

function linker:start_connect()
	if self._opt.link == 'tcp' then
		local conf = self._opt.tcp
		self._log:info(string.format("Connecting to %s:%d", conf.host, conf.port))
		local sock, err = socket.open(conf.host, conf.port)
		if not sock then
			local err = string.format("Cannot connect to %s:%d. err: %s", conf.host, conf.port, err or "")
			self._log:error(err)
			return nil, err
		end
		self._log:notice(string.format("Connected to %s:%d", conf.host, conf.port))

		if conf.nodelay then
			socketdriver.nodelay(sock)
		end

		self._socket = sock
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
			end
		end)

		self._port = port
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

return linker 
