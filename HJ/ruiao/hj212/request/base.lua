local class = require 'middleclass'
local types = require 'hj212.types'
local pfinder = require 'hj212.utils.pfinder'

local req = class('hj212.request.base')

local finder = pfinder(types.COMMAND, 'hj212.command')

function req:initialize(command, need_ack)
	self._session = nil
	self._command = command
	self._need_ack = need_ack == nil and true or need_ack -- default is true
end

function req:command()
	return self._command
end

function req:need_ack()
	return self._need_ack
end

function req:session()
	return self._session
end

function req:set_session(session)
	self._session = session
end

--- Creator: function(command, need_ack, params)
function req:encode(creator)
	assert(creator, "Creator missing")
	assert(type(creator) == 'function', "Creator must be function")

	local cmd = self._command:command()
	local params = self._command:encode()

	--local p = packet:new(client.sys, cmd, client.passwd, client.devid, self._need_ack, params)
	local p = assert(creator(cmd, self._need_ack, params))
	if self._session then
		p:set_session(self._session)
	end
	return p
end

function req:decode(packet)
	local params = packet:params()
	local cmd = packet:command()

	local m, err = pfinder(cmd)
	assert(m, err)

	local obj = m:new()
	obj:decode(params)

	self._command = obj

	self._need_ack = packet:need_ack()
	self._session = packet:session()

	return {
		sys = packet:system(),
		passwd = packet:passwd(),
		devid = packet:device_id()
	}
end

return req
