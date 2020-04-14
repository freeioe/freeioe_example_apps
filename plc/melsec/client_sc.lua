--- The client implemented by socketchannel of skynet

local class = require 'middleclass'
local base = require 'melsec.client'
local socketchannel = require 'socketchannel'
local stream_buffer = require 'app.utils.stream_buffer'

local client = class('FREEIOE_APP_PLC_MELSEC_CLIENT', base)

function client:initialize(...)
	base.initialize(self, ...)
	self._buf = stream_buffer:new(0xFFFF)
	self._lock = nil
end

function client:set_comm_cb(cb)
	self._comm_cb = cb
end

function client:connect()
	local conn_path = self:conn_path()
	assert(conn_path:proto() == 'tcp', 'Only TCP is supported')
	self._channel = socketchannel.channel({
		host = conn_path:address(),
		port = conn_path:port(),
		overload = function(...)
			return self:sock_overload(...)
		end
	})
	return self._channel:connect(true)

	--return self:register_session()
end

function client:sock_process(req, sock)

	while true do
		local data = sock:read()
		if not data then
			break
		end

		if self._comm_cb then
			self._comm_cb('RECV', data)
		end

		self._buf:append(data)

		local raw = self._buf:concat()

		local r, reply, index = xpcall(self.on_reply, debug.traceback, self, req, raw)
		if not r then
			return false, reply, index
		end

		if reply then
			self._buf:pop(index - 1)
			return true, reply
		end
	end
end

function client:sock_overload(is_overload)
	if is_overload then
		self:close()
	end
end

function client:close()
	self._channel:close()
	return true
end

function client:request(request, response)
	assert(request.to_hex, "Request needs to be one object")
	local session = request:session()

	if not self._channel then
		return nil, "Channel not initialized"
	end
	while self._lock do
		skynet.sleep(5)
	end

	self._lock = {}

	local raw = request:to_hex()

	if self._comm_cb then
		self._comm_cb('WRITE', raw)
	end

	local r, resp, err = pcall(self._channel.request, self._channel, raw, function(sock)
		return self:sock_process(request, sock)
	end)
	self._lock = nil

	---print(r, resp, err)
	if not r then
		return nil, resp, err
	end
	return response(resp, err)
end

return client
