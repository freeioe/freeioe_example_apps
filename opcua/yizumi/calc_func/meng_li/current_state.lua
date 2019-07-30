local class = require 'middleclass'

local calc = class("CALC_FUNCION_MENG_LI_CS")

function calc:initialize(app, dev, input, enable_sub)
	self._app = app
	self._dev = dev
	self._input = input
	self._enable_sub = enable_sub
end

function calc:start(ua_client)
	if self._enable_sub then
		-- Subscribe nodes
	else
		---get opcua node
	end
end


function calc:run()
	local app = self._app
	local dev = self._dev

	if not app:connected() then
		-- offline
		return dev:set_input_prop(self._input.name, 'value', -1)
	end

	if app._err_state then
		return dev:set_input_prop(self._input.name, 'value', app._err_state)
	end

	if dev:get_input_prop('IdleState', 'value') == 1 then
		-- IDLE
		return dev:set_input_prop(self._input.name, 'value', 1)
	end
	if dev:get_input_prop('MaintainenceState', 'value') == 1 then
		return dev:set_input_prop(self._input.name, 'value', 4)
	end
	return dev:set_input_prop(self._input.name, 'value', 0)
end

return calc
