local app_port = require 'app.port'
local app_base = require 'app.base'
local pair_serial = require 'pair_test.serial'
local pair_ms = require 'pair_test.master_slave'
local cjson = require 'cjson.safe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("PORT_TEST_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._name

	--- 增加设备实例
	local inputs = {
		{name="master_info", desc="master port info", vt="string"},
		{name="master_count", desc="master process count", vt="int"},
		{name="master_failed", desc="master process failed", vt="int"},
		{name="master_passed", desc="master process passed", vt="int"},
		{name="master_droped", desc="master process droped", vt="int"},

		{name="slave_info", desc="master port info", vt="string"},
		{name="slave_count", desc="slave process count", vt="int"},
		{name="slave_failed", desc="slave process failed", vt="int"},
		{name="slave_passed", desc="slave process passed", vt="int"},
		{name="slave_droped", desc="slave process droped", vt="int"},
	}

	local meta = self._api:default_meta()
	meta.name = "Port Test Device"
	meta.description = "Port Test Device Meta"

	self._dev = self._api:add_device(sn, meta, inputs)

	self._port_master = {
		port = "/dev/ttyS1",
		--port = "/tmp/ttyS10",
		baudrate = 115200
	}

	self._port_slave = {
		port = "/dev/ttyS2",
		--port = "/tmp/ttyS11",
		baudrate = 115200
	}

	self._test = pair_serial:new(self)
	self._test_case = pair_ms:new(self, 10, 256)

	self._sys:fork(function()
		self._test:open(self._port_master, self._port_slave)
		self._test:run(self._test_case)
	end)

	return true
end

--- 应用退出函数
function app:on_close(reason)
	if self._port then
		self._port:close(reason)
		self._serial:close(reason)
	end
end

--- 应用运行入口
function app:on_run(tms)
	local dev = self._dev
	if not self._info_set then
		dev:set_input_prop('master_info', 'value', cjson.encode(self._port_master))	
		dev:set_input_prop('slave_info', 'value', cjson.encode(self._port_slave))	
		self._info_set = true
	end

	local report = self._test_case:report()

	dev:set_input_prop('master_count', 'value', report.master.count)
	dev:set_input_prop('master_failed', 'value', report.master.failed)
	dev:set_input_prop('master_passed', 'value', report.master.passed)
	dev:set_input_prop('master_droped', 'value', report.master.droped)

	dev:set_input_prop('slave_count', 'value', report.slave.count)
	dev:set_input_prop('slave_failed', 'value', report.slave.failed)
	dev:set_input_prop('slave_passed', 'value', report.slave.passed)
	dev:set_input_prop('slave_droped', 'value', report.slave.droped)

	return 1000 --下一采集周期为1秒
end

--- 返回应用对象
return app
