local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'

local sbat_pwr = class("FREEIOE_STANDBY_POWER_STATUS_CLASS")

local sbat_power_fp = "/sys/class/gpio/sbat_power/value"

function sbat_pwr:initialize(app, sys)
	self._app = app
	self._sys = sys
	if lfs.attributes(sbat_power_fp, "mode") then
		self._enabled = true
	end
end

function sbat_pwr:inputs()
	if self._enabled then
		return {
			{
				name = 'sbat_pwr',
				desc = 'Standby battery power status',
				vt = "int",
			}
		}
	else
		return {}
	end
end

function sbat_pwr:read_status()
	local s = sysinfo.cat_file(sbat_power_fp)
	if tonumber(s) == 0 then
		self._dev:set_input_prop('sbat_pwr', 'value', 0)
	else
		self._dev:set_input_prop('sbat_pwr', 'value', 1)
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
end

return sbat_pwr
