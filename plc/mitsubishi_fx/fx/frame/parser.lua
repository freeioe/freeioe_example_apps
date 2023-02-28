local types = require 'fx.frame.types'
local fx_req = require 'fx.frame.req'
local fx_resp = require 'fx.frame.resp'
local fx_nak = require 'fx.frame.nak'
local fx_ack = require 'fx.frame.ack'

return function(raw, index)
	local head = string.byte(raw, index)
	if head == types.ENQ then
		return fx_req:new()
	elseif head == types.STX then
		return fx_resp:new()
	elseif head == types.ACK then
		return fx_ack:new()
	elseif head == types.NAK then
		return fx_nak:new()
	else
		return nil
	end
end
