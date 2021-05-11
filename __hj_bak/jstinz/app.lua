local ioe = require 'ioe'
local base = require 'app.base'
local master = require 'modbus.master.skynet'

local app = base:subclass("FREEIOE_HJ_JSTINZ_APP")
app.static.API_VER = 10

---
function app:on_init()
	local log = self:log_api()
	local conf = self:app_conf()

	if ioe.developer_mode() then
		conf.serial = conf.serial or {
			port = "/tmp/ttyS3",
			baudrate = 9600,
			data_bits = 8,
			parity = "NONE",
			stop_bits = 1,
			flow_control = "OFF"
		}
		conf.codcr_1001_opt = {
		}
	end
end

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local conf = self:app_conf()
	local log = self:log_api()

	local sn = sys_id.."."..conf.dev_sn

	local meta = self._api:default_meta()
	meta.name = "JiangSu TINZ "..conf.dev_type
	meta.manufacturer = "江苏天泽环保科技有限公司"
	meta.description = "江苏天泽环保-"..conf.dev_type

	local inputs = require(string.lower(conf.dev_type)..'.inputs')
	local outputs = require(string.lower(conf.dev_type)..'.outputs')
	local worker = require(string.lower(conf.dev_type)..'.worker')
	local worker_opt = conf[string.lower(conf.dev_type)..'_opt']


	self._dev = self._api:add_device(sn, meta, inputs, outputs)
	self._worker = worker:new(self, conf.unit, self._dev, worker_opt)

	if ioe.developer_mode() then
		self._modbus = master:new('TCP', {link='serial', serial = conf.serial})
	else 
		self._modbus = master:new('RTU', {link='serial', serial = conf.serial})
	end

	--- 设定通讯口数据回调
	self._modbus:set_io_cb(function(io, unit, msg)
		self._dev:dump_comm(io, msg)
	end)

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

	local r, err = self._worker:run(self._modbus)
	if not r then
		self._log:error(err)
	end

	return conf.loop_gap or 1000
end

--- 返回应用对象
return app
