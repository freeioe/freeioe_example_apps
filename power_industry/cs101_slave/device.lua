local base = require 'iec60870.slave.common.device.unbalance'
local common_helper = require 'iec60870.slave.common.helper'

local device = base:subclass('CS101_SLAVE_APP_DEVICE_CLASS')

function device:initialize(addr, inputs)
	base.initialize(self, addr)
	self._inputs = inputs
end

function device:get_snapshot()
	-- Get input type list
	local sp_list = {}
	local me_list = {}
	local it_list = {}
	for _, v in ipairs(self._inputs) do
		if v.name == 'SP' then
			table.insert(sp_list, v)
		end
	end

	--- Get data snapshot??? and then create data updated mark?
	local sp_data_list = {}
	for _, v in ipairs(sp_list) do
		local val, timestamp, quality = v:get_input_value()
		table.insert(sp_data_list, common_helper.make_sp_na(v.addr, val, timestamp))
		-- TODO: limit count
	end

	return {sp_data_list}
end

function device:has_spontaneous()
	return false
end

function device:get_spontaneous()
	return false
end

function device:get_class2_data()
	return nil
end

return device
