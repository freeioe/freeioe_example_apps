local class = require 'middleclass'
local helper = require 'm1c.frame.helper'

local base = class('LUA_FX_FRAME_BASE')

function base:initialize()
end

function base:valid_hex(raw, index)
end

-- return next raw index
function base:from_hex(raw, index)
	assert(false, 'Not implemented')
	return index
end

-- return raw string
function base:to_hex()
	assert(false, "not implemented")
	return ''
end

function base:__totable()
	return "Not implemented"
end

function base:__tostring()
	helper.tostring(self:__totable())
end

return base
