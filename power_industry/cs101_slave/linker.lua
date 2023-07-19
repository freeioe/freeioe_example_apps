local base = require 'iec60870.common.linker'
local skynet = require 'skynet'
local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local serial = require 'serialdriver'
local linker_tcp_server = require 'linker.tcp_server'
local linker_tcp_client = require 'linker.tcp_client'
local linker_serial = require 'linker.serial'

local linker = base:subclass("LUA_APP_LINKER_CLASS")

--- 
-- linker_type: tcp/serial
function linker:initialize(link, opt, log)
	base.initialize(self)

	-- Set default link to serial
	self._link = link or opt.link or 'serial'
	self._opt = opt
	self._log = log

	self._closing = false
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
	while not self._handler:connected() and t_left > 0 do
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

	return self._handler:write(raw)
end

function linker:connect_proc()
	local connect_gap = 100 -- one second
	self._log:debug("connection proc enter...")
	while not self._closing do
		if self._closing then
			break
		end

		local r, err = self:start_connect()
		if r then
			self._log:error("Start connection failed", err)
			break
		end

		self._log:error("Wait for retart connection", connect_gap)

		self._connection_wait = {}
		skynet.sleep(connect_gap, self._connection_wait)
		self._connection_wait = nil

		connect_gap = connect_gap * 2
		if connect_gap > 64 * 100 then
			connect_gap = 100
		end
	end

	self._log:debug("connection proc exit...")
end

function linker:start_connect()
	local handler = nil
	if self._link == 'tcp.client' then
		handler = linker_tcp_client:new(self, self._opt, self._log)
	end
	if self._link == 'tcp.server' then
		handler = linker_tcp_server:new(self, self._opt, self._log)
	end
	if self._link == 'serial' then
		handler = linker_serial:new(self, self._opt, self._log)
	end

	if not handler then
		return false, "Unknown Link Type"
	end

	if handler:open() then
		self._handler = handler
		return true
	end
	return false
end

function linker:watch_handler()
	self._handler:watch()

	if self._closing then
		return
	end

	--- reconnection
	skynet.timeout(100, function()
		self:connect_proc()
		self:watch_handler()
	end)
end

function linker:open()
	self._log:debug("Linker open...")
	if self._socket or self._port then
		return nil, "Already started"
	end

	self._closing = false

	skynet.timeout(100, function()
		self:connect_proc()
		self:watch_handler()
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
