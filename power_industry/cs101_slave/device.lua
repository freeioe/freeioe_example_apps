local base = require 'iec60870.slave.common.device.unbalance'

local device = base:subclass('CS101_SLAVE_APP_DEVICE_CLASS')

function device:initialize(addr)
	base.initialize(self, addr)
end

function device:get_snapshot()
	return {}
end

function device:has_spontaneous()
	return false
end

function device:get_spontaneous()
	return false
end

return device
