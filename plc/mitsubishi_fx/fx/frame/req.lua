local base = require 'fx.frame.base'
local types = require 'fx.frame.types'
local helper = require 'fx.frame.helper'

local req = base:subclass('LUA_FX_FRAME_REQ')

local HEAD_LEN = 1 --[[ENQ]] + 2 --[[DevAddr]] + 2 --[[PC_Addr]] + 2 --[[CMD]] + 1 --[[WAIT]]
local TAIL_LEN = 2 --[[LEN]] + 2 --[[CS]]

function req:initialize(proto_type, dev_no, pc_no, cmd, timeout, start, count, data)
	self._proto_type = proto_type
	self._dev_no = dev_no or 0
	self._pc_no = pc_no or 0xFF
	self._cmd = cmd or 'BR'
	self._timeout = timeout or 0
	self._start = start or ''
	self._count = count or 0
	self._data = data
end

function req:DEV_NO()
	return self._dev_no
end

function req:PC_NO()
	return self._pc_no
end

function req:CMD()
	return self._cmd
end

function req:TIMEOUT()
	return self._timeout
end

function req:START()
	return self._start
end

function req:COUNT()
	return self._count
end

function req:DATA()
	return self._data
end

function req:valid_hex(raw, index)
	local head = string.byte(raw, index)
	local ind = index or 1
	if head ~= types.ENQ then
		return false, ind + 1
	end
	if string.len(raw) - ind + 1 < HEAD_LEN then
		return false, ind
	end
	local cmd = string.sub(raw, ind + 5)

	local len = HEAD_LEN + fx_helper.cmd_addr_len(cmd) + TAIL_LEN
	local elen = len
	if self._proto_type == types.PROTO_TYPE_4 then
		--[[ \r\n LF.CR ]]
		if string.len(raw) - ind + 1 < len + 2 then
			return false, ind
		end

		local end_t = string.sub(raw, ind + len, ind + len + 1)
		if end_t ~= '\r\n' then
			return false, ind + 1
		end
		elen = len + 2
	else
		if string.len(raw) - ind + 1 < len then
			return false, ind
		end
	end

	local cs_data = string.sub(raw, ind + 1, ind + len - 3)
	local cs = helper.sum(cs_data)
	if cs ~= string.sub(raw, ind + len - 2, ind + len -1) then
		return false, ind + 1
	end
	return true, ind + elen
end

function req:from_hex(raw, index)
	local ind = (index or 1) + 1
	self._dev_no = tonumber('0x'..string.sub(raw, ind, ind + 1))
	ind = ind + 2
	self._pc_no = tonumber('0x'..string.sub(raw, ind, ind + 1))
	ind = ind + 2
	self._cmd = string.sub(raw, ind, ind + 1)
	ind = ind + 2
	self._timeout = tonumber('0x'..string.sub(raw, ind, ind))
	ind = ind + 1

	local addr_len = fx_helper.cmd_addr_len(self._cmd)
	self._addr = string.sub(raw, ind, ind + addr_len - 1)
	ind = ind + addr_len
	self._count = tonumber('0x'..string.sub(raw, ind, ind + 1))
	ind = ind + 2
	ind = ind + 2
	if self._proto_type == types.PROTO_TYPE_4 then
		ind = ind + 2
	end
	return ind
end

function req:to_hex()
	assert(self._cmd, 'Command is nil')
	assert(self._start, 'Start address is nil')
	local data = table.concat({
		string.format('%02X%02X', self._dev_no, self._pc_no),
		self._cmd,
		string.format('%01X', self._timeout),
		self._start,
		string.format('%02X', self._count),
	})
	local cs = helper.sum(data)

	if self._proto_type == types.PROTO_TYPE_4 then
		return string.char(types.ENQ)..data..cs..'\r\n'
	else
		return string.char(types.ENQ)..data..cs
	end
end

return req
