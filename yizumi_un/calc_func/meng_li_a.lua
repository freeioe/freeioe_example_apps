local class = require 'middleclass'

local calc = class("CALC_FUNCION_MENG_LI_A")

function calc:initialize(app, input, node_finder)
	self._app = app
	self._input = input
	self._finder = node_finder
	--- TODO
end

function calc:run(dev)
	local app = self._app
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
