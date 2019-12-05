local app_base = require 'app.base'

local app = app_base:subclass('EXAMPLE_CALC_APP_IN_GUIDE')
app.static.API_VER = 5

function app:on_init()
	-- 计算帮助模块初始化
	local calc = self:create_calc()
end

function app:on_start()
	local source_device_sn = 'xxxxxxxxxxxxx.xxx'
	self._calc:add('unique_name_for_calc', {
		{ sn = source_device_sn, input = 'temperature', prop='value'}
	}, function(temperature)
		if temperature > 40 then
			---  turn the fan on
			self:control_fan(true)
			self._fan_on = true
			return
		end
		if self._fan_on and temperature < 30 then
			--- turn the fan off
			self:control_fan(false)
			self._fan_off = false
			return
		end
	end)
end

function app:control_fan(on_off)
	local control_device_sn = 'xxxxxxxxxxxxxxxx.xxx'
	local device = self._api:get_device(control_device_sn)
	if device then
		local out_value = on_off and 1 or 0
		return device:set_output_prop('set_f', 'value', out_value)
	end
end

return app
