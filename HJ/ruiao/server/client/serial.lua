local base = require 'server.client.base'
local crc16 = require 'hj212.utils.crc_serial_le'

local client = base:subclass("hj212_server.server.client.tcp")

--- 
-- stream_type: tcp/serial
function client:initialize(server, serial, port, connection_timeout)
	base.initialize(self, server, {crc = crc16})
	assert(serial, "serial missing")
	assert(port, "port missing")
	self._serial = serial
	self._port = port
	self._closing = nil
	self._requests = {}
	self._results = {}
	self._buf = {}
	self._sys = server:sys_api()
	self._last_in = self._sys:now()
	self._connection_timeout = connection_timeout or 30 -- in seconds
end

function client:host()
	return self._port.port
end

function client:port()
	return 0
end

function client:on_recv(data)
	self:dump_raw('IN', data)
	table.insert(self._buf, data)
	self._last_in = self._sys:now()

	if self._buf_wait then
		self._sys:wakeup(self._buf_wait)
	end
end

function client:send(session, raw_data, timeout)
	if not self._serial then
		return nil, "No serial opened"
	end
	local timeout = self:timeout()

	local t = {}
	self._requests[session] = t

	local cur = 0
	while not self._closing and cur < self:retry() do
		local serial = self._serial
		if not serial then
			self._results[session] = {false, "Serial closed"}
			break
		end

		if cur ~= 0 then
			self:log('warning', 'Resend request', session, cur)
		end

		local r, err = serial:write(raw_data)
		if not r then
			self._results[session] = {false, err}
			break
		end

		self:dump_raw('OUT', raw_data)

		-- Wait for response
		self._sys:sleep(timeout, t)
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
	if not self._serial then
		return nil, "No serial opened"
	end

	self:dump_raw('OUT', raw_data)

	return self._serial:write(raw_data)
end

function client:start()
	self._sys:fork(function()
		self:work_proc()
	end)
	self._sys:fork(function()
		self:send_req()
	end)

	self._sys:fork(function()
		self:check_last_in()
	end)

	return true
end

function client:close()
	if not self._serial then
		return nil, "Already closed"
	end
	if self._closing then
		return nil, "Client is closing"
	end

	self:on_disconnect() -- serial is open always

	self._closing = {}

	self._sys:wait(self._closing)
	self._closing = nil
	self._serial = nil

	self:log('debug', "Client close done!")

	return true
end

function client:send_req()
	while not self._closing and self._serial do
		self:send_nowait('##00010077QN=20150530190615121;ST=31;CN=2013;PW=123456;MN=88888880000001;Flag=3;CP=&&&&2414\r\n')
		self._sys:sleep(1000)
		self:send_nowait('##00010077QN=20150530191136001;ST=31;CN=2023;PW=123456;MN=88888880000001;Flag=3;CP=&&&&34A9\r\n')
		self._sys:sleep(1000)
		self:send_nowait('##00010077QN=20150530191653001;ST=31;CN=1073;PW=123456;MN=88888880000001;Flag=3;CP=&&&&9F4B\r\n')
		self._sys:sleep(3000)
	end
end

function client:check_last_in()
	while not self._closing and self._serial do
		if self._sys:now () - self._last_in > self._connection_timeout * 1000 then
			self:log('warning', "Client receive timeout close client!")
			return self:close()
		end
		self._sys:sleep(1000)
	end
end

function client:work_proc()
	self:log('info', "Client workproc starting...")
	while not self._closing and self._serial do
		local r, err = xpcall(self.process_serial_data, debug.traceback, self)
		if not r then
			self:log('error', err)
		end
	end
	if self._closing then
		for session, co in pairs(self._requests) do
			self._results[session] = {false, "Serial closing"}
			self._sys:wakeup(co)
		end
		self._sys:wakeup(self._closing)
	end
	self:log('info', "Client workproc quited")
end

function client:process_serial_data()
	while not self._closing and self._serial do
		if #self._buf == 0 then
			self._buf_wait = {}
			self._sys:sleep(1000, self._buf_wait)
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
						self._sys:wakeup(req_co)
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
