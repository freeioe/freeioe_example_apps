local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local sapp = require 'app.base'
local ioe = require 'ioe'

local app = sapp:subclass("freeioe.other.dnat_forward")
app.static.API_VER = 10

function app:on_init()
	self._down_sent = 0
	self._down_recv = 0
	self._down_count = 0
	self._up_sent = 0
	self._up_recv = 0
	self._up_count = 0
end

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._name

	--- 增加设备实例
	local inputs = {
		{name="down_sent", desc="down peer sent bytes", vt="int", unit="bytes"},
		{name="down_recv", desc="down peer received bytes", vt="int", unit="bytes"},
		{name="down_count", desc="down peer connection count", vt="int"},
		{name="up_sent", desc="up peer sent bytes", vt="int", unit="bytes"},
		{name="up_recv", desc="up peer received bytes", vt="int", unit="bytes"},
		{name="up_count", desc="up peer connection count", vt="int"},
	}

	local meta = self._api:default_meta()
	meta.name = "DNAT Forward"
	meta.inst = self._name
	meta.description = "DNAT Forward"

	local conf = self:app_conf()

	if ioe.developer_mode() then
		conf.down = {
			host = '192.168.1.248',
			port = 80
		}
		conf.up = {
			host = '0.0.0.0',
			port = 6080
		}
	end

	self._dev = self._api:add_device(sn, meta, inputs)
	self._closing = false

	self._sys:timeout(10, function()
		self:listen_proc()
	end)

	return true
end

function app:listen_proc()
	self._log:info("Start server listen...")

	while not self._closing do
		local r, err = self:start_listen()
		if r then
			break
		end
		self._log:error(err)

		self._sys:sleep(3000)

		self._log:debug("Wait for restart listen socket")
	end

	assert(self._server_socket)
end

function app:watch_down_socket(fd, up_fd)
	while true do
		local data, err = socket.read(fd)
		if not data then
			self._log:trace(string.format("Down read failed %s", err))
			socket.close(up_fd)
			break
		end
		self._down_recv = self._down_recv + string.len(data)

		local r, err = socket.write(up_fd, data)
		if not r then
			socket.close(fd)
			self._log:trace(string.format("Up write failed %s", err))
			break
		end
		self._up_sent = self._up_sent + string.len(data)
	end
end

function app:watch_client_socket(fd, addr)
	local c = self:app_conf()
	if not c.down then
		socket.close(fd)
	end

	local conf = c.down
	local host = assert(conf.host)
	local port = assert(conf.port)

	self._log:trace(string.format("Connecting to %s:%d", host, port))
	local sock, err = socket.open(host, port)
	if not sock then
		local err = string.format("Cannot connect to %s:%d. err: %s", host, port, err or "")
		self._log:error(err)
		socket.close(fd)
		return
	end

	self._log:trace(string.format("Connected to %s:%d", conf.host, conf.port))
	socketdriver.nodelay(sock)
	self._down_count = self._down_count + 1

	self._sys:fork(function()
		self:watch_down_socket(sock, fd)
	end)

	while true do
		local data, err = socket.read(fd)
		if not data then
			self._log:trace(string.format("Up read failed %s", err))
			break
		end
		self._up_recv = self._up_recv + string.len(data)

		local r, err = socket.write(sock, data)
		if not r then
			self._log:trace(string.format("Up write failed %s", err))
			break
		end
		self._down_sent = self._down_sent + string.len(data)
	end

	-- close down socket
	socket.close(sock)
	-- try to close socket
	socket.close(fd)
end

function app:start_listen()
	local c = self:app_conf()
	local conf = assert(c.up)
	local host = conf.host or '0.0.0.0'
	local port = conf.port or 6000

	self._log:info(string.format("Listen on %s:%d", host, port))
	local sock, err = socket.listen(host, port)
	if not sock then
		return nil, string.format("Cannot listen on %s:%d. err: %s", host, port, err or "")
	end
	self._server_socket = sock

	socket.start(sock, function(fd, addr)
		self._log:debug(string.format("New connection (fd = %d, %s)", fd, addr))
		self._up_count = self._up_count + 1

		--- Set no delay
		socketdriver.nodelay(fd)

		--- Bind socket to current service
		socket.start(fd)

		self._sys:fork(function()
			self:watch_client_socket(fd, addr)
		end)
	end)

	--- When listen socket closed then restart it
	socket.onclose(sock, function()
		self._log:warning("Listen socket closed!")
		self._server_socket = nil

		if not self._closing then
			self._sys:timeout(1000, function()
				self:listen_proc()
			end)
		end
	end)

	return true
end

--- 应用退出函数
function app:on_close(reason)
	self._closing = true

	--- Close linsten socket
	if self._server_socket then
		socket.close(self._server_socket)
	end

	while self._server_socket do
		self._log:warning("Wait for listen socket closed")
		self._sys:sleep(1000)
	end

	return true
end

--- 应用运行入口
function app:on_run(tms)
	self._dev:set_input_prop('down_sent', 'value', self._down_sent)
	self._dev:set_input_prop('down_recv', 'value', self._down_recv)
	self._dev:set_input_prop('down_count', 'value', self._down_count)
	self._dev:set_input_prop('up_sent', 'value', self._up_sent)
	self._dev:set_input_prop('up_recv', 'value', self._up_recv)
	self._dev:set_input_prop('up_count', 'value', self._up_count)
	return 1000 --下一采集周期为1秒
end

--- 返回应用对象
return app

