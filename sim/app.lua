local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'

local app = class("FREEIOE_DATA_SIM_APP")
app.static.API_VER = 4

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = self._sys:data_api()
	self._log = sys:logger()

	self._devs = {}
end

function app:start()
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value, timestamp, priv)
		end,
		on_command = function(app, sn, command, param, priv)
		end,
		on_ctrl = function(app, command, param, priv)
			self._log:trace('on_ctrl', app, command, param, priv)
		end,
	})

	local dev_count = self._conf.device_count or 4
	local tag_count = self._conf.tag_count or 4

	for d = 1, dev_count do
		local dev_sn = self._sys:id()..'.'..self._name..'.'..d
		local inputs = {}

		local outputs = {}
		for i = 1, tag_count do
			inputs[#inputs + 1] = {
				name = 'tag'..i,
				desc = 'input '..i,
			}
		end

		local meta = self._api:default_meta()
		meta.name = "Data Simulation"
		meta.description = "Data Simulation device"
		meta.series = "X"
		local dev = self._api:add_device(dev_sn, meta, inputs)
		table.insert(self._devs, dev)
	end

	return true
end

function app:close(reason)
	--print(self._name, reason)
end

function app:run(tms)
	local tag_count = self._conf.tag_count or 4
	local run_loop = self._conf.run_loop or 100 -- ms

	for _, dev in ipairs(self._devs) do
		for i = 1, tag_count do
			dev:set_input_prop('tag'..i, 'value', math.random(0xFFFFFFFF))
		end
	end

	return run_loop
end

return app
