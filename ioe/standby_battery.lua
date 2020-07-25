local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local sum = require 'summation'
local ioe = require 'ioe'

local sbat_pwr = class("FREEIOE_STANDBY_POWER_STATUS_CLASS")

local sbat_power_fp = "/sys/class/gpio/sbat_power/value"

function sbat_pwr:initialize(app, sys)
	self._app = app
	self._sys = sys
	if lfs.attributes(sbat_power_fp, "mode") then
		self._enabled = true

		self._sum = sum:new({
			file = true,
			save_span = 60 * 5,
			key = 'standby_battery',
			span = 'never',
			path = sysinfo.data_dir()
		})

		self._start_time = nil
		self._last_update = nil
	end
end

function sbat_pwr:inputs()
	if self._enabled then
		return {
			{
				name = 'sbat_pwr',
				desc = 'Standby battery power time',
				vt = "int",
				unit = 'sec'
			}
		}
	else
		return {}
	end
end

function sbat_pwr:read_status()
	local s = sysinfo.cat_file(sbat_power_fp)
	local now = ioe.time()

	if tonumber(s) == 0 then
		if self._sum:get('pwr') ~= 0 then
			self._dev:set_input_prop('sbat_pwr', 'value', self._sum:get('pwr'))
			self._sum:reset()
			self._last_update = now - 9 -- next second will upload 0
		end
		if self._start_time then
			self._start_time = nil --- clear the start time
		end
	else
		if not self._start_time then
			self._start_time = now --- set the start time
		end
		self._sum:set('pwr', math.floor(now - self._start_time))
	end

	--- Update the value every ten seconds
	if not self._last_update or now - self._last_update >= 10 then
		self._dev:set_input_prop('sbat_pwr', 'value', self._sum:get('pwr'))
		self._last_update = now
	end

	self._cancel_timer = self._sys:cancelable_timeout(1000, function()
		self:read_status()
	end)
end

function sbat_pwr:start(dev)
	self._dev = dev
	if self._enabled then
		self:read_status()
	end
end

function sbat_pwr:stop()
	if self._cancel_timer then
		self._cancel_timer()
		self._cancel_timer = nil
	end
	if self._sum then
		self._sum:save()
	end
end

return sbat_pwr
