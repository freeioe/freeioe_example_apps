local class = require 'middleclass'
local skynet = require 'skynet'
local serial = require 'serialdriver'

local mserial = class("Modbus_Serial_Skynet")

--- 
-- stream_type: tcp/serial
function mserial:initialize(port_opt)
	self._closing = false
	self._port_opt = port_opt
	self._requests = {}
	self._results = {}
end

function mserial:set_io_cb(cb)
	self._io_cb = cb
end

--- Timeout: ms
function mserial:request(unit, data, timeout)
	if self._requests[key] then
		return nil, "Key already used!!!"
	end

	local t_left = timeout
	while not self._port and t_left > 0 do
		skynet.sleep(100)
		t_left = t_left - 1000
		if self._closing then
			return nil, "Connection closing!!!"
		end
	end
	if t_left <= 0 then
		return nil, "Not connected!!"
	end

	if self._port then
		--- Serial modbus
		while self._locked do
			skynet.sleep(10)
		end
		self._locked = true
	end

	if self._io_cb then
		self._io_cb('OUT', unit, data)
	end

	--local basexx = require 'basexx'
	--print(os.date(), 'Send request', key)
	--print(os.date(), 'OUT:', basexx.to_hex(apdu_raw))
	local r, err = self._port:write(data)

	local t = {}
	self._requests[key] = t

	skynet.sleep(timeout / 10, t)

	self._requests[key] = nil

	if self._port then
		self._locked = nil
	end
	
	local result = self._results[key] or {false, "Timeout"}
	self._results[key] = nil
	--[[
	if not result[1] then
		print(os.date(), 'Request failed', key, table.unpack(result))
	else
		print(os.date(), 'Request done', key)
	end
	]]--
	return table.unpack(result)
end

function mserial:connect_proc()
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
end

function mserial:start_connect()
	local opt = self._port_opt
	local port = serial:new(opt.port,
							opt.baudrate or 9600,
							opt.data_bits or 8,
							opt.parity or 'NONE',
							opt.stop_bits or 1,
							opt.flow_control or "OFF")

	local r, err = port:open()
	if not r then
		return nil, "Failed open serial port:"..opt.port..", error: "..err)
	end

	port:start(function(data, err)
		-- Recevied Data here
		if data then
			self:process(data)
		else
			skynet.error(err)
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

function mserial:process(data)
	--local basexx = require 'basexx'
	--print(os.date(), 'IN:', basexx.to_hex(data))
	self._apdu:append(data)
	if self._apdu_wait then
		skynet.wakeup(self._apdu_wait)
	end

	if self._io_cb then
		local unit = self._apdu:current_unit()
		self._io_cb('IN', unit, data)
	end
end


function mserial:start()
	if self._port then
		return nil, "Already started"
	end

	self._closing = false

	skynet.timeout(100, function()
		self:connect_proc()
	end)

	skynet.fork(function()
		while not self._closing do
			self._apdu:process(function(key, unit, pdu)
				assert(key)
				--local basexx= require 'basexx'
				if unit then
					--print(os.date(), 'apdu_process_cb', key, unit, basexx.to_hex(pdu))
				else
					--print(os.date(), 'apdu_process_cb', key, pdu)
				end
				local req_co = self._requests[key]
				if req_co then
					local err_flag = false
					if unit then
						local fc = string.unpack('I1', pdu)
						err_flag = fc & 0x80 ~= 0
						if err_flag then
							-- TODO: 
							self._results[key] = {false, pdu, key}
						else
							self._results[key] = {pdu}
						end
					else
						self._results[key] = {false, pdu, key}
					end

					skynet.wakeup(req_co)
				else
					skynet.error('Coroutine for key: '..key..' missing!')
				end
			end)
			self._apdu_wait = {}
			skynet.sleep(1000, self._apdu_wait)
			self._apdu_wait = nil
		end
	end)
	return true
end

function mserial:stop()
	self._closing = true
	if self._apdu_wait then
		skynet.wakeup(self._apdu_wait) -- wakeup the process co
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

return mserial 
