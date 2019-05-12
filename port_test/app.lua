local lfs = require 'lfs'
local cjson = require 'cjson.safe'
local app_port = require 'app.port'
local app_base = require 'app.base'
local pair_serial = require 'pair_test.serial'
local pair_ms = require 'pair_test.master_slave'
local pair_pp = require 'pair_test.ping_pong'

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
		{ name = "current", desc = "current run test case", vt = "string" },
		{ name = "master_info", desc = "master port info", vt = "string" },
		{ name = "master_count", desc = "master process count", vt = "int" },
		{ name = "master_failed", desc = "master process failed", vt = "int" },
		{ name = "master_passed", desc = "master process passed", vt = "int" },
		{ name = "master_droped", desc = "master process droped", vt = "int" },
		{ name = "master_send_speed", desc = "master send speed", },
		{ name = "master_recv_speed", desc = "master recv speed", },

		{ name = "slave_info", desc = "slave port info", vt = "string" },
		{ name = "slave_count", desc = "slave process count", vt = "int" },
		{ name = "slave_failed", desc = "slave process failed", vt = "int" },
		{ name = "slave_passed", desc = "slave process passed", vt = "int" },
		{ name = "slave_droped", desc = "slave process droped", vt = "int" },
		{ name = "slave_send_speed", desc = "slave send speed", },
		{ name = "slave_recv_speed", desc = "slave recv speed", },

		{ name = "loop_info", desc = "loop port info", vt = "string" },
		{ name = "loop_count", desc = "loop process count", vt = "int" },
		{ name = "loop_failed", desc = "loop process failed", vt = "int" },
		{ name = "loop_passed", desc = "loop process passed", vt = "int" },
		{ name = "loop_droped", desc = "loop process droped", vt = "int" },
		{ name = "loop_send_speed", desc = "loop send speed", },
		{ name = "loop_recv_speed", desc = "loop recv speed", },
	}

	local commands = {
		{ name = "abort", desc = "abort current run test case" },
		{ name = "master_slave", desc = "start master slave test" },
		{ name = "loop", desc = "start loop test" },
	}

	local meta = self._api:default_meta()
	meta.name = "Port Test Device"
	meta.description = "Port Test Device Meta"

	self._dev = self._api:add_device(sn, meta, inputs)

	local ttyS = nil
	if lfs.attributes('/tmp/ttyS1', 'mode') then
		ttyS = '/tmp/ttyS'
	else
		if lfs.attributes('/dev/ttymxc1', 'mode') then
			ttyS = '/dev/ttymxc'
		else
			ttyS = '/dev/ttyS'
		end
	end
	ttyS = '/dev/ttyUSB'

	local ttyS1 = self._conf.ttyS1 or ((self._conf.ttyS or ttyS) ..'0')
	local ttyS2 = self._conf.ttyS2 or ((self._conf.ttyS or ttyS) ..'1')
	local baudrate = self._conf.baudrate or 9600
	local count = self._conf.count or 1000
	local max_size = self._conf.max_msg_size or 256
	local auto_run = self._conf.auto or 'loop'
	self._log:notice("Serial Port Test", ttyS1, ttyS2, auto_run)

	self._port_master = {
		port = ttyS1,
		baudrate = baudrate,
	}

	self._port_slave = {
		port = ttyS2,
		baudrate = baudrate,
	}

	self._test = pair_serial:new(self)
	self._ms_test = pair_ms:new(self, count, max_size)
	self._loop_test = pair_pp:new(self, count, max_size, true)
	self._test:open(self._port_master, self._port_slave)

	if auto_run == 'master_slave' then
		self:start_master_slave_test()
	end
	if auto_run == 'loop' then
		self:start_loop_test()
	end
	self._current_test = auto_run

	return true
end

function app:_run_current()
	self._sys:timeout(1000, function()
		self._log:warning("Start test", self._current_test)
		local r, err = self._sys:cloud_post('enable_data_one_short', 3600)
		if not r then
			self._log:error("ENABLE_DATA_ONE_SHORT FAILED", err)
		else
			self._log:notice("ENABLE_DATA_ONE_SHORT DONE!")
		end

		self._log:trace("Start test", self._current_test)
		local r, err = self._test:run(self._current)
		if not r then
			self._log:error("RUN TEST CASE FAILED", err)
		end

		local r, err = self._sys:cloud_post('enable_data_one_short', 60)
		if not r then
			self._log:error("ENABLE_DATA_ONE_SHORT CLOSE FAILED", err)
		else
			self._log:notice("ENABLE_DATA_ONE_SHORT CLOSE DONE!")
		end

		self._current = nil
	end)
end

function app:start_master_slave_test()
	if self._current then
		return nil, "Running"
	end

	self._current = self._ms_test
	self._current_test = 'master_slave'

	return self:_run_current()
end

function app:start_loop_test()
	if self._current then
		return nil, "Running"
	end

	self._current = self._loop_test
	self._current_test = 'loop'
	
	return self:_run_current()
end

function app:on_command(src_app, command, params)
	if command == 'master_slave' then
		return self:start_master_slave_test()
	end
	if command == 'loop' then
		return self:start_loop_test()
	end
	if command == 'abort' then
		if not self._current then
			return nil, "Not running"
		end

		self._test:abort()
	end
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
		dev:set_input_prop('loop_info', 'value', cjson.encode(self._port_master))	
		self._info_set = true
	end

	dev:set_input_prop('current', 'value', self._current_test)

	local report = self._ms_test:report()

	dev:set_input_prop('master_count', 'value', report.master.count)
	dev:set_input_prop('master_failed', 'value', report.master.failed)
	dev:set_input_prop('master_passed', 'value', report.master.passed)
	dev:set_input_prop('master_droped', 'value', report.master.droped)
	dev:set_input_prop('master_send_speed', 'value', report.master.send_speed)
	dev:set_input_prop('master_recv_speed', 'value', report.master.recv_speed)

	dev:set_input_prop('slave_count', 'value', report.slave.count)
	dev:set_input_prop('slave_failed', 'value', report.slave.failed)
	dev:set_input_prop('slave_passed', 'value', report.slave.passed)
	dev:set_input_prop('slave_droped', 'value', report.slave.droped)
	dev:set_input_prop('slave_send_speed', 'value', report.slave.send_speed)
	dev:set_input_prop('slave_recv_speed', 'value', report.slave.recv_speed)

	local report = self._loop_test:report()
	dev:set_input_prop('loop_count', 'value', report.count)
	dev:set_input_prop('loop_failed', 'value', report.failed)
	dev:set_input_prop('loop_passed', 'value', report.passed)
	dev:set_input_prop('loop_droped', 'value', report.droped)
	dev:set_input_prop('loop_send_speed', 'value', report.send_speed)
	dev:set_input_prop('loop_recv_speed', 'value', report.recv_speed)

	return 1000 --下一采集周期为1秒
end

--- 返回应用对象
return app
