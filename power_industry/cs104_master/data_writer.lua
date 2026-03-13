local class = require 'middleclass'
local write_sco = require 'iec60870.master.common.write_sco'
local write_dco = require 'iec60870.master.common.write_dco'
local write_rco = require 'iec60870.master.common.write_rco'

local writer = class('LUA_IEC60870_FRAME_DATA_WRITER')

function writer:initialize(slave)
	self._slave = assert(slave)
end

local write_map = {
	SP = function(slave, addr, value)
		local w = write_sco:new(slave, addr)
		return w(value == 1)
	end,
	DP = function(slave, addr, value, se)
		local w = write_dco:new(slave, addr)
		return w(value == 1)
	end,
	ST = function(slave, addr, value, se)
		local w = write_rco:new(slave, addr)
		return w(value == 1)
	end,
}

-- Make asdu
function writer:__call(tname, addr, value)
	local func = write_map[tname]
	if not func then
		return nil, "Not support "..tname
	end
	return func(self._slave, addr, value)
end

return writer
