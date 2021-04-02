local class = require 'middleclass'
local logger = require 'hj212.logger'
local types = require 'hj212.types'
local pfinder = require 'hj212.utils.pfinder'

local server = class('hj212.server.base')

function server:initialize()
end

function server:log(level, ...)
	logger.log(level, ...)
end

function server:start()
	assert(nil, 'Not implemented')
end

function server:stop()
	assert(nil, 'Not implemented')
end

return server
