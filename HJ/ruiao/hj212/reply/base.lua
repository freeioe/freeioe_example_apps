local class = require 'middleclass'
local types = require 'hj212.types'
local pfinder = require 'hj212.utils.pfinder'

local resp = class('hj212.reply.base')

local finder = pfinder(types.COMMAND, 'hj212.command')

function resp:initialize(session, command)
	self._session = session
	self._command = command
	self._need_ack = need_ack ~= nil and need_ack or false -- default is false
end

function resp:session()
	return self._session
end

function resp:command()
	return self._command
end

function resp:need_ack()
	return self._need_ack
end

-- creator: function(cmd, need_ack, params)
function resp:encode(creator)
	assert(creator, 'Creator missing')
	assert(type(creator) == 'function', 'Creator must be function')

	local cmd = self._command:command()
	local params = self._command:encode()

	--local p = packet:new(types.SYSTEM.REPLY, cmd, client.passwd, client.devid, self._need_ack, params)
	local p = assert(creator(cmd, self._need_ack, params))
	p:set_session(self._session)
	return p
end

function resp:decode(packet)
	local params = packet:params()
	local cmd = packet:command()

	local m, err = pfinder(cmd)
	assert(m, err)

	local obj = m:new()
	obj:decode(params)

	self._command = obj

	self._need_ack = packet:need_ack()
	self._session = packet:session()

	assert(packet:system() == types.SYSTEM.REPLY)

	return {
		sys = packet:system(),
		passwd = packet:passwd(),
		devid = packet:device_id()
	}
end

return resp
