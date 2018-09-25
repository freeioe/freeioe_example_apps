local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'

local app = class("FREEIOE_APP_SIM_TANK_CLASS")
app.API_VER = 1

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = self._sys:data_api()
	self._log = sys:logger()

	self._values = {
		tank_1 = 0,
		tank_2 = 0,
		top_left = 0,
		top_right = 1,
		middle = 1,
		bottom_left = 0,
		bottom_right = 1,
		motor_left = 1,
		motor_right = 0
	}
end

function app:start()
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
			self._log:trace('on_output', app, sn, output, prop, value)
			if sn ~= self._dev_sn then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end
			if self._values[output] ~= nil then
				self._values[output] = math.floor(tonumber(value))
			end
			self:set_inputs()
			return true, "done"
		end,
		on_command = function(app, sn, command, param)
			if sn ~= self._dev_sn then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end
			if command == 'top_left_close' then
				self._values.top_left = 1
			end
			self:set_inputs()
		end,
		on_ctrl = function(app, command, param, ...)
			self._log:trace('on_ctrl', app, command, param, ...)
		end,
	})

	local dev_sn = self._sys:id()..'.'..self._name
	--[[
	local inputs = {
		{
			name = 'em_test',
			desc = 'emergency test',
			vt = "int"
		}
	}
	]]--
	local inputs = {}

	local outputs = {}
	for k, v in pairs(self._values) do
		inputs[#inputs + 1] = {
			name = k,
			desc = 'input '..k,
			vt = "int"
		}
		outputs[#outputs + 1] = {
			name = k,
			desc = 'input '..k,
			vt = "int"
		}
	end
	local cmds = {
		{
			name = "top_left_close",
			desc = "Force uploading NTP/NETWORK information",
		},
		{
			name = "top_left_open",
			desc = "Force NTP service reload configurations",
		},
	}

	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "Tank Simulation"
	meta.description = "Tank Simulation device"
	meta.series = "X"
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs, cmds)

	return true
end

function app:close(reason)
	--print(self._name, reason)
end

function app:set_inputs()
	for k,v in pairs(self._values) do
		self._dev:set_input_prop(k, 'value', v)
	end
end

function app:run(tms)
	local vals = self._values

	-- TODO: Logic
	vals.tank_1 = vals.tank_1 + 1
	vals.tank_2 = vals.tank_2 + 1

	self:set_inputs()

	--self._dev:set_input_prop_emergency('em_test', 'value', os.time())

	return 1000 * 5 -- five seconds
end

return app
