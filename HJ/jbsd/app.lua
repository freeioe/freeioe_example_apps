local ioe = require 'ioe'
local base = require 'app.base'
--local mserial = require 'mserial'
local master = require 'modbus.master.skynet'

local app = base:subclass("JBSD_MODBUS_APP")
app.static.API_VER = 9

---
function app:on_init()
	local log = self:log_api()
	local conf = self:app_conf()

	if ioe.developer_mode() then
		conf.unit = 17
		conf.serial = conf.serial or {
			port = "/tmp/ttyS2",
			baudrate = 19200,
			data_bits = 8,
			parity = "NONE",
			stop_bits = 1,
			flow_control = "OFF"
		}
		conf.wl_1a1_opt = {
			fm_type = 'NEWER_15_01',
			mr_flow = 100,
			mr_liquid_level = 10,
			mr_I1 = 10,
			mr_I2 = 10,
			mr_I3 = 10,
			mr_I4 = 10,
		}
	end
end

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local conf = self:app_conf()
	local log = self:log_api()

	local sn = conf.dev_sn_prefix and sys_id.."."..conf.dev_sn or conf.dev_sn

	local meta = self._api:default_meta()
	meta.name = "JBSD Modbus "..conf.dev_type
	meta.manufacturer = "北京九波声迪科技有限公司"
	meta.description = "北京九波声迪科"..conf.dev_type

	local inputs = require(string.lower(conf.dev_type)..'.inputs')
	local outputs = require(string.lower(conf.dev_type)..'.outputs')
	local worker = require(string.lower(conf.dev_type)..'.worker')
	local worker_opt = conf[string.lower(conf.dev_type)..'_opt']


	self._dev = self._api:add_device(sn, meta, inputs, outputs)
	self._worker = worker:new(self, conf.unit, self._dev, worker_opt)

	self._modbus = master:new('RTU', {link='serial', serial = conf.serial})
	return self._modbus:start()
end

--- 应用退出函数
function app:on_close(reason)
	if self._modbus then
		self._modbus:stop()
		self._modbus = nil
	end
end

--- 应用运行入口
function app:on_run(tms)
	local conf = self:app_conf()

	self._worker:run(self._modbus)

	return conf.loop_gap or 1000
end

--- 返回应用对象
return app
