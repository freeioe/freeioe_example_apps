local base_app = require 'app.base'
local event = require 'app.event'

local app = base_app:subclass("FREEIOE_DATA_SIM_APP")
app.static.API_VER = 4

function app:initialize(name, sys, conf)
	base_app.initialize(self, name, sys, conf)
end

function app:on_start()

	local inputs = { { name = 'count', desc = 'Event count', vt = 'int' } }
	local commands = { { name = 'trigger', desc = 'Trigger an event now' } }

	local meta = self._api:default_meta()
	meta.name = "Event Simulation"
	meta.description = "Event Simulation device"
	meta.series = "X"

	local dev_sn = self._sys:id()..'.'..self._name
	self._dev = self._api:add_device(dev_sn, meta, inputs, nil, commands)
	self._count = 0

	self._dev:set_input_prop('count', 'value', self._count)

	return true
end

function app:on_command(app_src, sn, command, param, priv)
	if command ~= 'trigger' then
		return nil, "Command not supported!"
	end

	self._count = self._count + 1
	self._dev:set_input_prop('count', 'value', self._count)

	local data = { gateway = self._sys:id(), count = self._count, time=os.date() }

	self._dev:fire_event(event.LEVEL_INFO, event.EVENT_APP, 'Triggered Event', data)

	return true
end

return app
