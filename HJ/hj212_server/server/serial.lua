local skynet = require 'skynet'
local cjson = require 'cjson.safe'
local serialdriver = require 'serialdriver'
local client = require 'server.client.serial'
local base = require 'server.base'

local server = base:subclass("hj212_sever.server.serial")

--- 
--
function server:initialize(app, opt)
	assert(app, "App missing")
	assert(opt, "Option missing")
	assert(opt.port, "Port missing")
	base.initialize(self, app)
	self._opt = opt
	self._closing = false
	self._client = nil
end

function server:listen_proc()
	local log = self._app:log_api()

	local sleep_time = 100 -- one second
	while not self._closing do
		if not self._serial then
			skynet.sleep(sleep_time, self)
			local serial, err = self:create_serial()
			if serial then
				self._serial = serial
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

	--- Close port
	if self._serial then
		self._serial:close()
		self._serial = nil
	end

	-- Cleanup client
	if self._client then
		self._client:close()
		self._client = nil
	end

	-- Wakeup  closing
	skynet.wakeup(self._closing)
end

function server:create_serial()
	local log = self._app:log_api()
	local opt = self._opt
	local nodelay = self._nodelay

	opt.baudrate = opt.baudrate or 9600
	opt.data_bits = opt.data_bits or 8
	opt.parity = opt.parity or 'NONE'
	opt.stop_bits = opt.stop_bits or 1
	opt.flow_control = opt.flow_control or 'OFF'

	log:notice(string.format("Open serial %s", cjson.encode(opt)))
	local serial = serialdriver:new(opt.port, opt.baudrate, opt.data_bits, opt.parity, opt.stop_bits, opt.flow_control)
	local r, err = serial:open()
	if not r then
		return nil, string.format("Cannot open serial: %s. err: %s", opt.port, err or "unknown")
	end

	serial:start(function(data, err)
		if not self._client then
			local cli = client:new(self, serial, opt)
			if self:valid_connection(cli) then
				self._client = cli
				cli:start()
			else
				cli:close()
			end
		else
			self._client:on_recv(data)
		end
	end)
	return sock
end

function server:start()
	if self._serial then
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
	skynet.wait(self._closing)
	assert(self._serial == nil)
	self._closing = nil

	if self._client then
		self._client:close()
	end
	self._client = nil

	return base.stop(self)
end

return server 
