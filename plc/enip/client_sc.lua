--- The client implemented by socketchannel of skynet

local base = require 'enip.ab.client.unconnected'
local command = require 'enip.command.base'
local reply_parser = require 'enip.reply.parser'
local socketchannel = require 'socketchannel'

local client = base:subclass('FREEIOE_APP_PLC_ENIP_CIP_CLIENT')

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

function client:set_logger(log)
	self._log = log
end

function client:connect()
	local conn_path = self:conn_path()
	local log = self._log
	assert(conn_path:proto() == 'tcp', 'Only TCP is supported')
	self._channel = socketchannel.channel({
		host = conn_path:address(),
		port = conn_path:port(),
		nodelay = true,
		response = function(...)
			local ret = {xpcall(self.sock_dispatch, debug.traceback, self, ...)}
			if not ret[1] then
				local err = ret[2]
				if err ~= socketchannel.error then
					err = table.concat(ret, '', 2)
				end
				if log then
					log:error("Socket error:", err)
				end

				if self.reconnect then
					self:reconnect()
				end

				return nil, err
			end
			return table.unpack(ret, 2)
		end,
		overload = function(...)
			return self:sock_overload(...)
		end,
		auth = function(sock)
			local r, err = self:register_session()
			if not r then
				log:error('register_session error', err)
				assert(r, err)
			end
			--[[
			local ret, err = pcall(self.register_session, self)
			if not ret then
				if log then
					log:error("Auth method error", err)
				end
			end
			]]--
		end
	})

	self._channel:connect(false) -- non-block mode connect
	return true
end

function client:sock_dispatch(sock)
	local min_size = command.min_size()
	local raw, err = sock:read(min_size)

	local cmd, data_len = command.parse_header(raw)

	if data_len > 0 then
		local data_raw, err = sock:read(data_len)
		if not data_raw then
			return nil, err
		end
		raw = raw..data_raw
	end

	if self._hex_dump then
		self._hex_dump('IN', raw)
	end

	local reply, err = reply_parser(cmd, raw)
	if not reply then
		self._log:error('reply parser error:', err)
		return nil, err
	end
	local session = reply:session()

	return session:context(), reply ~= nil, reply or err
end

function client:sock_overload(is_overload)
	if is_overload then
		self:close()
	end
end

function client:invalid_session()
	local r, err = self:register_session()
	if not r then
		self._log:error("Invalid session try to register session again but failed", err)
	end
end

function client:close()
	self._channel:close()
	return true
end

function client:set_dump(func)
	self._hex_dump = func
end

function client:request(request, response)
	assert(request.to_hex, "Request needs to be one object")
	assert(request.session, "Session missing")
	local session = request:session()

	if not self._channel then
		return nil, "Channel not initialized"
	end

	local req_raw = request:to_hex()
	if self._hex_dump then
		self._hex_dump('OUT', req_raw)
	end
	local r, resp, err = pcall(self._channel.request, self._channel, req_raw, session:context())
	if not r then
		return nil, resp, err
	end
	return response(resp, err)
end

return client
