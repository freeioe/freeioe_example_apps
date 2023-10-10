local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local basexx = require 'basexx'
local cjson = require 'cjson.safe'
local sapp = require 'app.base'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = sapp:subclass("EXAMPLE_APP_INFINITE_CONN_TEST")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	sapp.initialize(self, name, sys, conf)

	self._test_count = 0
	self._srv_host = ''
	self._srv_port = 0
end

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._name

	--- 增加设备实例
	local inputs = {
		{ name="count", desc="Test counts", vt="int" },
		{ name="srv_host", desc="Socket server address", vt="string" },
		{ name="srv_port", desc="Socket server port", vt="int" },
	}

	local meta = self._api:default_meta()
	meta.name = "Infinite socket connect test"
	meta.inst = self._name
	meta.description = "Infinate test result"

	self._dev = self._api:add_device(sn, meta, inputs)

	local conf = self._conf
	self._srv_host = conf.host
	self._srv_port = conf.port
	self._min_recv = conf.min_recv

	self._sys:timeout(10, function()
		self:connect_proc()
	end)

	return true
end

function app:connect_proc()
	self._log:info("Start socket connection", err)

	local connect_gap = 1000
	while true do
		self._sys:sleep(connect_gap)
		local r, err = self:start_connect()
		if r then
			break
		end

		connect_gap = connect_gap * 2
		if connect_gap > 64 * 1000 then
			connect_gap = 1000
		end
		self._log:debug("Wait for restart connection", connect_gap)
	end

	self:watch_client_socket()
end

function app:watch_client_socket()
	local recv_bytes = 0
	while self._socket do
		local data, err = socket.read(self._socket)	
		if not data then
			self._log:info("Socket disconnected", err)
			break
		end
		self._dev:dump_comm('SOCKET-IN', data)
		self._test_count = self._test_count + 1
		recv_bytes = recv_bytes + string.len(data)
		if recv_bytes > self._min_recv then
			self._log:info("Socket received data, test done")
			break
		end
	end

	if self._socket then
		local to_close = self._socket
		self._socket = nil
		socket.close(to_close)
	end

	--- reconnection
	self._sys:timeout(10, function()
		self:connect_proc()
	end)
end

function app:start_connect()
	self._log:info(string.format("Connecting to %s:%d", self._srv_host, self._srv_port))
	local sock, err = socket.open(self._srv_host, self._srv_port)
	if not sock then
		local err = string.format("Cannot connect to %s:%d. err: %s", self._srv_host, self._srv_port, err or "")
		self._log:error(err)
		return nil, err
	end
	self._log:info(string.format("Connected to %s:%d", self._srv_host, self._srv_port))

	if self._conf.nodelay then
		socketdriver.nodelay(sock)
	end

	self._socket = sock
	return true
end

--- 应用退出函数
function app:on_close(reason)
	if self._socket then
		local to_close = self._socket
		self._socket = nil
		socket.close(to_close)
	end
end

--- 应用运行入口
function app:on_run(tms)
	self._dev:set_input_prop('count', 'value', self._test_count)
	self._dev:set_input_prop('srv_host', 'value', self._srv_host)
	self._dev:set_input_prop('srv_port', 'value', self._srv_port)
	return 1000 --下一采集周期为1秒
end

--- 返回应用对象
return app

