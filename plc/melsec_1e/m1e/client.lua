local class = require 'middleclass'
local skynet = require 'skynet'
local stream = require 'm1c.stream'
local m1c_req = require 'm1c.frame.req'
local m1c_ack = require 'm1c.frame.ack'
local m1c_frame_parser = require 'm1c.frame.parser'
local buffer = require 'm1c.buffer'

local client = class("LUA_FX_CLIENT_CLASS")

--- 
-- stream_type: tcp/serial
function client:initialize(opt, log)
	self._closing = false
	self._opt = opt
	self._log = log
	self._buf = buffer:new(1024)
	self._request = nil
	self._result = nil
end

function client:set_io_cb(cb)
	self._io_cb = cb
end

--- Timeout: ms
function client:read(dev_no, cmd, start, count, timeout)
	assert(dev_no, 'Device address invalid')
	assert(cmd, 'Request command invalid')
	assert(start, 'Memory address start invalid')

	local count = count or 1
	local timeout = timeout or 1000
	print(start, count, timeout)

	local req = m1c_req:new(self._opt.proto_type, dev_no, self._opt.pc_no, cmd, 0, start, count)
	if self._request then
		return nil, "Device already in reading/writing!!!"
	end

	local t_left = timeout
	while self._request and t_left >= 0 do
		skynet.sleep(10)
		t_left = t_left - 100
	end
	if t_left < 0 then
		return nil, 'Request timeout!!!!'
	end
	self._request = req

	local apdu_raw = req:to_hex()
	self._stream:write(apdu_raw, timeout)

	local t = {}
	self._request_wait = t

	skynet.sleep(timeout / 10, self._request_wait)

	self._request_wait = nil
	self._request = nil
	
	local result = self._result or {false, "Timeout"}
	self._result = nil
	if not result[1] then
		--print(os.date(), 'Request failed', dev_no, table.unpack(result))
	else
		--print(os.date(), 'Request done', dev_no)
		local ack = m1c_ack:new(self._opt.proto_type, dev_no, self._opt.pc_no)
		self._stream:write(ack:to_hex(), false)
	end
	return table.unpack(result)
end

--- Timeout: ms
function client:write(dev_no, cmd, addr, count, data, timeout)
	assert(dev_no, 'Device address invalid')
	assert(cmd, 'Request command invalid')
	assert(addr, 'Memory address invalid')

	local timeout = timeout or 1000
	print(addr, count, timeout)

	local req = m1c_req:new(self._opt.proto_type, dev_no, self._opt.pc_no, cmd, 0, addr, count, data)
	if self._request then
		return nil, "Device already in reading/writing!!!"
	end

	local t_left = timeout
	while self._request and t_left >= 0 do
		skynet.sleep(10)
		t_left = t_left - 100
	end
	if t_left < 0 then
		return nil, 'Request timeout!!!!'
	end
	self._request = req

	local apdu_raw = req:to_hex()
	self._stream:write(apdu_raw, timeout)

	local t = {}
	self._request_wait = t

	skynet.sleep(timeout / 10, self._request_wait)

	self._request_wait = nil
	self._request = nil
	
	local result = self._result or {false, "Timeout"}
	self._result = nil
	if not result[1] then
		--print(os.date(), 'Request failed', dev_no, table.unpack(result))
	else
		--print(os.date(), 'Request done', dev_no)
	end
	return table.unpack(result)
end


function client:frame_process()
	while not self._closing do
		::next_frame::
		--- Smaller size
		local frame, r, index
		if self._buf:len() < 5 then
			goto next_apdu
		end

		frame = m1c_frame_parser(tostring(self._buf), 1)
		if not frame then
			self._buf:pop(1)
			goto next_frame
		end

		r, index, err = frame:valid_hex(tostring(self._buf), 1)
		if not r then
			if index ~= 1 then
				self._buf:pop(index - 1)
				self._log:error('Frame error:'..err)
				goto next_frame
			end
		else
			local raw = self._buf:sub(1, index - 1)
			self._buf:pop(index - 1)
			local r = frame:from_hex(raw, 1)
			assert(r == index)
			local dev_no = frame:DEV_NO()
			local basexx= require 'basexx'
			if dev_no then
				print(os.date(), 'apdu_process_cb', dev_no, basexx.to_hex(raw))
			else
				print(os.date(), 'apdu_process_cb', dev_no, raw)
			end

			local req = self._request

			if not self._request or not self._request_wait then
				self._log:error('Request missing or timeout!')
				goto next_frame
			end

			if req:DEV_NO() ~= dev_no then
				self._log:error('DEV NO not match!')
				goto next_frame
			end

			self._result = frame
			self._log:debug('Result frame for dev_no:'..dev_no)

			skynet.wakeup(self._request_wait)

			goto next_frame
		end

		::next_apdu::
		self._apdu_wait = {}
		skynet.sleep(1000, self._apdu_wait)
		self._apdu_wait = nil
	end
end

function client:start()
	if self._stream then
		return nil, "Already started"
	end

	self._stream = stream:new(self._opt, {
		on_recv = function(raw)
			--local basexx = require 'basexx'
			--print(os.date(), 'IN:', basexx.to_hex(raw))
			self._buf:append(raw)
			if self._apdu_wait then
				skynet.wakeup(self._apdu_wait)
			end

			if self._io_cb then
				local unit = self._request and self._request:DEV_NO() or -1
				self._io_cb('IN', unit, raw)
			end
		end,
		on_send = function(raw)
			if self._io_cb then
				local unit = self._request and self._request:DEV_NO() or -1
				self._io_cb('OUT', unit, raw)
			end
		end,
	})
	self._stream:start()

	--- Start frame process co
	skynet.fork(function()
		self:frame_process()
	end)

	return true
end

function client:stop()
	self._closing = true

	--- Abort apdu_wait
	if self._apdu_wait then
		skynet.wakeup(self._apdu_wait) -- wakeup the process co
	end

	-- Stop stream
	self._stream:stop()

	-- Abort request
	if self._request_wait then
		skynet.wakeup(self._request_wait)
	end
end

return client 
