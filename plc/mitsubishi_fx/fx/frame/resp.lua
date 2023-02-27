local basexx = require 'basexx'
local base = require 'fx.frame.base'
local types = require 'fx.frame.types'
local helper = require 'fx.frame.helper'

local resp = base:subclass('LUA_FX_FRAME_RESP')

local HEAD_LEN = 1 --[[STX]] + 2 --[[DevAddr]] + 2 --[[PC_Addr]]
local TAIL_LEN = 1 --[[ETX]] + 2 --[[CS]]

function resp:initialize(proto_type, dev_no, pc_no, data)
	self._proto_type = proto_type
	self._dev_no = dev_no or 0
	self._pc_no = pc_no or 0xFF
	self._data = data
end

function resp:DEV_NO()
	return self._dev_no
end

function resp:PC_NO()
	return self._pc_no
end

function resp:DATA()
	return self._data
end

function resp:valid_hex(raw, index)
	local head = string.byte(raw, index)
	local ind = index or 1
	if head ~= types.STX then
		return false, ind + 1
	end
	if string.len(raw) - ind + 1 < HEAD_LEN then
		return false, ind
	end

	local ei = ind + 6
	for i = ei, string.len(raw) do
		if string.byte(raw, i) == types.ETX then
			ei = i
		end
	end

	if ei == ind + 5 then
		return false, ind
	end
	if ei + 2 > string.len(raw) then
		return false, ind
	end

	local cs_data = string.sub(raw, ind + 1, ei)
	local cs = helper.sum(cs_data)
	if cs ~= string.sub(raw, ei + 1, ei + 2) then
		return false, ind + 1
	end
	return true, ei + 3
end

function resp:from_hex(raw, index)
	local ind = (index or 1) + 1
	self._dev_no = tonumber('0x'..string.sub(raw, ind, ind + 1))
	ind = ind + 2
	self._pc_no = tonumber('0x'..string.sub(raw, ind, ind + 1))
	ind = ind + 2

	local ei = ind
	for i = ei, string.len(raw) do
		if string.byte(raw, i) == types.ETX then
			ei = i
		end
	end

	self._data = basexx.from_hex(string.sub(raw, ind, ei - 1))
	return ei + 3
end

function resp:to_hex()
	local no_str = string.format('%02X%02X', self._dev_no, self._pc_no)
	local data = basexx.to_hex(helper.to_hex(self._data))
	local data = no_str..data..types.ETX

	local cs = helper.sum(data)

	if self._proto_type == types.PROTO_TYPE_4 then
		return string.char(types.STX)..data..cs..'\r\n'
	else
		return string.char(types.STX)..data..cs
	end
end

return resp
