local types = require 'm1c.frame.types'
local m1c_req = require 'm1c.frame.req'
local m1c_resp = require 'm1c.frame.resp'
local m1c_nak = require 'm1c.frame.nak'
local m1c_ack = require 'm1c.frame.ack'

return function(raw, index)
	local head = string.byte(raw, index)
	if head == types.ENQ then
		return m1c_req:new()
	elseif head == types.STX then
		return m1c_resp:new()
	elseif head == types.ACK then
		return m1c_ack:new()
	elseif head == types.NAK then
		return m1c_nak:new()
	else
		return nil
	end
end
