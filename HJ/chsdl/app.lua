local ioe = require 'ioe'
local base = require 'app.base'
--local mserial = require 'mserial'
local master = require 'modbus.master.skynet'

local app = base:subclass("CHSDL_MODBUS_APP")
app.static.API_VER = 9

---
function app:on_init()
	local log = self:log_api()
	local conf = self:app_conf()

	if ioe.developer_mode() then
		conf.unit = 1
		conf.serial = conf.serial or {
			port = "/tmp/ttyS2",
			baudrate = 9600,
			data_bits = 8,
			parity = "NONE",
			stop_bits = 1,
			flow_control = "OFF"
		}
		conf.scs_900uv_opt = {
			enable_plc = true,
			a_s = 1.4,
			plc_unit = 1,
			plc_serial = {
				port = "/tmp/ttyS2",
				baudrate = 19200,
				data_bits = 8,
				parity = "EVEN",
				stop_bits = 1,
				flow_control = "OFF"
			},
			wet_low = 0,
			wet_high = 100,
			dust_low = 0,
			dust_high = 1000,
			pa_low = 0,
			pa_high = 100,
			temp_low = -30,
			temp_high = 100,
			pa_s_low = -30,
			pa_s_high = 100,
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
	meta.name = "SDL "..conf.dev_type
	meta.manufacturer = "北京雪迪龙科技股份有限公司"
	meta.description = "北京雪迪龙"..conf.dev_type

	local inputs = require(string.lower(conf.dev_type)..'.inputs')
	local outputs = require(string.lower(conf.dev_type)..'.outputs')
	local worker = require(string.lower(conf.dev_type)..'.worker')
	local worker_opt = conf[string.lower(conf.dev_type)..'_opt']


	self._dev = self._api:add_device(sn, meta, inputs, outputs)
	self._worker = worker:new(self, conf.unit, self._dev, worker_opt)

	self._modbus = master:new('RTU', {link='serial', serial = conf.serial})
	if conf.scs_900uv_opt.enable_plc then
		self._plc_modbus = master:new('RTU', {link='serial', serial = conf.scs_900uv_opt.plc_serial})
	end
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

	self._worker:run(self._modbus, self._plc_modbus)

	return conf.loop_gap or 1000
end

--- 返回应用对象
return app
