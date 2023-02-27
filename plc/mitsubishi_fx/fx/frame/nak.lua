local base = require 'fx.frame.base'
local types = require 'fx.frame.types'
local helper = require 'fx.frame.helper'

local nak = base:subclass('LUA_FX_FRAME_NAK')

local NAK_LEN = 1 + 2 + 2

function nak:initialize(proto_type, dev_no, pc_no)
	self._proto_type = proto_type
	self._dev_no = dev_no or 0
	self._pc_no = pc_no or 0xFF
end

function nak:DEV_NO()
	return self._dev_no
end

function nak:PC_NO()
	return self._pc_no
end

function nak:valid_hex(raw, index)
	local head = string.byte(raw, index)
	local ind = index or 1
	if head ~= types.NAK then
		return false, ind + 1
	end

	if self._proto_type == types.PROTO_TYPE_4 then
		if string.len(raw) - index + 1 < NAK_LEN + 2 then
			return false, ind
		end
		return true, ind + NAK_LEN + 2
	else
		if string.len(raw) - index + 1 < NAK_LEN then
			return false, ind
		end
		return true, ind + NAK_LEN
	end
end

function nak:from_hex(raw, index)
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

function nak:to_hex()
	local data = string.format('%02X%02X', self._dev_no, self._pc_no)
	if self._proto_type == _M.PROTO_TYPE_4 then
		return string.char(types.NAK)..data..'\r\n'
	else
		return string.char(types.NAK)..data
	end
end

return nak
