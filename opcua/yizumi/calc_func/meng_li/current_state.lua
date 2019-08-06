local class = require 'middleclass'

local calc = class("CALC_FUNCION_MENG_LI_CS")

function calc:initialize(app, dev, input, enable_sub)
	self._app = app
	self._dev = dev
	self._input = input
	self._enable_sub = enable_sub
end

function calc:start(ua_client)
	self._app:watch_input(self._input, 'IdleState', function(input, prop, value, timestamp, quality)
		--print('IdleState', value)
		if quality == 0 then
			self._idle_state = value
		else
			self._idle_state = 0
		end
		self:run()
	end)
	self._app:watch_input(self._input, 'MaintainenceState', function(input, prop, value, timestamp, quality)
		--print('MaintainenceState', value)
		if quality == 0 then
			self._maintainence_state = value
		else
			self._maintainence_state = 0
		end
		self:run()
	end)

	self._app:watch_input(self._input, 'AlarmState', function(input, prop, value, timestamp, quality)
		--print('AlarmState', value)
		if quality == 0 then
			self._alarm_state = value
		else
			self._alarm_state = nil
		end
		self:run()
	end)
end

function calc:stop()
	self._app:watch_input(self._input, 'IdleState', nil)
	self._app:watch_input(self._input, 'MaintainenceState', nil)
	self._app:watch_input(self._input, 'AlarmState', nil)
end

function calc:run()
	local app = self._app
	local dev = self._dev

	if not app:connected() then
		-- offline
		return dev:set_input_prop(self._input.name, 'value', -1)
	end

	if self._alarm_state ~= nil and self._alarm_state ~= 'NONE' then
		return dev:set_input_prop(self._input.name, 'value', self._alarm_state == 'ERROR' and 3 or 2 )
	end

	if self._idle_state == 1 then
		-- IDLE
		return dev:set_input_prop(self._input.name, 'value', 1)
	end
	if self._maintainence_state == 1 then
		return dev:set_input_prop(self._input.name, 'value', 4)
	end

	return dev:set_input_prop(self._input.name, 'value', 0)
end

return calc
