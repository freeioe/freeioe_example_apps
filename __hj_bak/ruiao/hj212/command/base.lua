local class = require 'middleclass'
local copy = require 'hj212.utils.copy'
local params = require 'hj212.params'
local packet = require 'hj212.packet'

local base = class('hj212.command.base')

function base:initialize(cmd, ATTRS)
	assert(ATTRS)
	self._command = cmd
	self._attrs = ATTRS
	self._params = params:new()
	for k, v in pairs(ATTRS) do
		assert(not self[k], 'Invalid attribute key')
		self[k] = v
		self._params:set(k, v)
	end
end

function base:command()
	return self._command
end

function base:params()
	return self._params
end

function base:add_tag(...)
	return self._params:add_tag(...)
end

function base:add_device(...)
	return self._params:add_device(...)
end

function base:encode()
	return self._params
end

function base:decode(params)
	local params = copy.deep(params)
	for k,v in pairs(self._attrs) do
		self[k] = params:get(k)
	end
	self._params = params
end

return base
