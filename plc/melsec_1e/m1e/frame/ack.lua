local base = require 'm1c.frame.base'
local types = require 'm1c.frame.types'
local helper = require 'm1c.frame.helper'

local ack = base:subclass('LUA_FX_FRAME_ACK')

local ACK_LEN = 1 + 2 + 2

function ack:initialize(proto_type, dev_no, pc_no)
	self._proto_type = proto_type
	self._dev_no = dev_no or 0
	self._pc_no = pc_no or 0xFF
end

function ack:DEV_NO()
	return self._dev_no
end

function ack:PC_NO()
	return self._pc_no
end

function ack:valid_hex(raw, index)
	local head = string.byte(raw, index)
	local ind = index or 1
	if head ~= types.ACK then
		return false, ind + 1
	end

	if self._proto_type == types.PROTO_TYPE_4 then
		if string.len(raw) - index + 1 < ACK_LEN + 2 then
			return false, ind
		end
		return true, ind + ACK_LEN + 2
	else
		if string.len(raw) - index + 1 < ACK_LEN then
			return false, ind
		end
		return true, ind + ACK_LEN
	end
end

function ack:from_hex(raw, index)
	local ind = (index or 1) + 1
	self._dev_no = tonumber('0x'..string.sub(raw, ind, ind + 1))
	ind = ind + 2
	self._pc_no = tonumber('0x'..string.sub(raw, ind, ind + 1))
	if self._proto_type == types.PROTO_TYPE_4 then
		return ind + 2 + 2
	else
		return ind + 2
	end
end

function ack:to_hex()
	local data = string.format('%02X%02X', self._dev_no, self._pc_no)
	if self._proto_type == types.PROTO_TYPE_4 then
		return string.char(types.ACK)..data..'\r\n'
	else
		return string.char(types.ACK)..data
	end
end

return ack
