local class = require 'middleclass'
local stateful = require 'stateful'

local req = class('LUA_FX_REQUEST')
req:include(stateful)

function req:initialize(client, req_frame, retry)
	self._client = client
	self._req_frame = req_frame
	self._retry = retry or 0
	self._result = nil
end

function req:DEV_NO()
	return self._req_frame:DEV_NO()
end

function req:RESULT()
	return self._result
end

function req:run(...)
	return self._client:do_request(self._req_frame, true)
end

function req:to_hex()
	return self._req_frame:to_hex()
end

function req:is_end()
	if self._retry > 0 then
		return true
	end
	self._retry = self._retry - 1
	return false
end

local req_resp = req:addState('STX')

function req_resp:run(resp)
	-- parse data
	self:gotoState('ACK')
	return true
end

function req_resp:is_end()
	return true
end

local req_ack = req:addState('ACK')

function req_ack:run(...)
	--- Send ACK
	self:gotoState(nil)
	return true
end

function req_ack:is_end()
	return true
end

local req_nak = req:addState('NAK')

function req_nak:run(...)
	--- Print error message or retry???
	self:gotoState(nil)
end

function req_nak:is_end()
	return true
end

return req
