--- The client implemented by socketchannel of skynet

local class = require 'middleclass'
local base = require 'enip.client.unconnected'
local enip_header = require 'enip.command.header'
local reply_parser = require 'enip.reply.parser'
local socketchannel = require 'socketchannel'

local client = class('FREEIOE_APP_PLC_ENIP_CIP_CLIENT', base)

local function protect_call(obj, func, ...)
	assert(obj and func)
	local f = obj[func]
	if not f then
		return nil, "Object has no function "..func
	end

	local ret = {xpcall(f, debug.traceback, obj, ...)}
	if not ret[1] then
		print(table.concat(ret, '', 2))
		return nil, table.concat(ret, '', 2)
	end
	return table.unpack(ret, 2)
end

function client:connect()
	local conn_path = self:conn_path()
	assert(conn_path:proto() == 'tcp', 'Only TCP is supported')
	self._channel = socketchannel.channel({
		host = conn_path:address(),
		port = conn_path:port(),
		response = function(...)
			local ret = {xpcall(self.sock_dispatch, debug.traceback, self, ...)}
			if not ret[1] then
				print(table.concat(ret, '', 2))
				--TODO: close the client?????

				if self.reconnect then
					self:reconnect()
				end

				return nil, table.concat(ret, '', 2)
			end
			return table.unpack(ret, 2)
		end,
		overload = function(...)
			return self:sock_overload(...)
		end
	})
	self._channel:connect(true)

	return self:register_session()
end

function client:sock_dispatch(sock)
	--print('sock_dispath start')
	local hdr_raw = sock:read(24)

	local header = enip_header:new()
	header:from_hex(hdr_raw)
	local session = header:session()

	--print(header:length())
	local data_raw = sock:read(header:length())

	local command, err = reply_parser(hdr_raw..data_raw)
	--print('sock_dispath end')

	return session:context(), command ~= nil, command or err
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
	assert(request.session, "Session missing")
	local session = request:session()

	if not self._channel then
		return nil, "Channel not initialized"
	end

	local r, resp, err = pcall(self._channel.request, self._channel, request:to_hex(), session:context())
	if not r then
		return nil, resp, err
	end
	return response(resp, err)
end

return client
