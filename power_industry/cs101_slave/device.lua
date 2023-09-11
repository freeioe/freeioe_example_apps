local class = require 'middleclass'
local common_helper = require 'iec60870.slave.common.helper'
local common_device = require 'iec60870.slave.common.device'
local ioe = require 'ioe'

local device = class('CS101_SLAVE_APP_DEVICE_CLASS')

function device:initialize(addr, mode, inputs, log)
	assert(addr)
	assert(mode)
	assert(log)
	self._inputs = assert(inputs)
	self._log = assert(log)
	self._device = common_device:new(addr, mode)
	--- create input map
	self._inputs_map = {}
	local now = ioe.now()

	local input_pools = {}
	self._input_pools = {}

	for _, v in ipairs(self._inputs) do
		local key = v.sn..'/'..v.name
		self._inputs_map[key] = true
		if not input_pools[v.ti] then
			input_pools[v.ti] = {}
		end
		table.insert(input_pools[v.ti], v)
	end

	local str = 'Device:'..addr..' mode:'..mode
	for k, v in pairs(input_pools) do
		table.sort(v, function (a, b)
			return a.addr < b.addr
		end)
		local base_addr = nil
		for _, vv in ipairs(v) do
			if not base_addr then
				base_addr = vv.addr - 1
			end
			if vv.addr ~= base_addr + 1 then
				log:error('Device:'..addr..' input sequence error found. ti:'..vv.ti..' addr:'..vv.addr)
			end
			base_addr = vv.addr
		end
		str = ' ti:'..k..' count:'..#v
		self._input_pools[k] = self._device:add_inputs(k, v)
	end
	log:info(str)
end

function device:DEVICE()
	return self._device
end

function device:check_input(sn, input)
	return self._inputs_map[sn..'/'..input]
end

function device:handle_input(sn, input, value, timestamp, quality)
	for _, v in ipairs(self._inputs) do
		if v.sn == sn and v.name == input then
			self._log:trace('set device input value ', v.name, value)
			local inputs = self._input_pools[v.ti]
			inputs:set_value(input, value, timestamp, quality)
			--[[
			if string.sub(v.ti, 1, 2) == 'SP' then
				self._sp_list:set_value(input, value, timestamp, quality)
			elseif string.sub(v.ti, 1, 2) == 'ME' then
				self._me_list:set_value(input, value, timestamp, quality)
			elseif string.sub(v.ti, 1, 2) == 'IT' then
				self._it_list:set_value(input, value, timestamp, quality)
			end
			]]--
		end
	end
end

return device
