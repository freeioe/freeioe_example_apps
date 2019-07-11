local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local serial = require 'serialdriver'
local basexx = require 'basexx'
local cjson = require 'cjson.safe'
local sapp = require 'app.base'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = sapp:subclass("RTU_EXAMPLE_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	sapp.initialize(self, name, sys, conf)

	self._log:debug("Port example application initlized")

	self._serial_sent = 0
	self._serial_recv = 0
	self._socket_sent = 0
	self._socket_recv = 0
	self._socket_peer = ''
end

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._name

	--- 增加设备实例
	local inputs = {
		{name="serial_sent", desc="Serial sent bytes", vt="int", unit="bytes"},
		{name="serial_recv", desc="Serial received bytes", vt="int", unit="bytes"},
		{name="socket_sent", desc="Socket sent bytes", vt="int", unit="bytes"},
		{name="socket_recv", desc="Socket received bytes", vt="int", unit="bytes"},
		{name="socket_peer", desc="Socket peer information", vt="string"}
	}

	local meta = self._api:default_meta()
	meta.name = "RTU Serial"
	meta.inst = self._name
	meta.description = "RTU Serial Meta"

	self._dev = self._api:add_device(sn, meta, inputs)

	local opt = self._conf.serial
	local port = serial:new(opt.port, opt.baudrate or 9600, opt.data_bits or 8, opt.parity or 'NONE', opt.stop_bits or 1, opt.flow_control or "OFF")
	local r, err = port:open()
	if not r then
		self._log:warning("Failed open port, error: "..err)
		return nil, err
	end

	port:start(function(data, err)
		-- Recevied Data here
		if data then
			self._dev:dump_comm('SERIAL-IN', data)
			self._serial_recv = self._serial_recv + string.len(data)

			--self._log:debug("Recevied data", basexx.to_hex(data))
			if self._socket then
				self._socket_sent = self._socket_sent + string.len(data)
				self._dev:dump_comm('SOCKET-OUT', data)
				socket.write(self._socket, data)
			end
		else
			self._log:error(err)
		end
	end)
	self._port = port

	self._sys:timeout(10, function()
		self:connect_proc()
	end)

	return true
end

function app:connect_proc()
	local connect_gap = 1000
	while true do
		self._sys:sleep(connect_gap)
		local r, err = self:start_socket()
		if r then
			break
		end
		self._log:error(err)

		connect_gap = connect_gap * 2
		if connect_gap > 60 * 1000 then
			connect_gap = 1000
		end
	end

	self:watch_socket()
end

function app:watch_socket()
	while self._socket or self._server_socket do
		if not self._socket then
			self._log:trace("Waiting for connection coming")
			self._sys:sleep(100)
		else
			local data, err = socket.read(self._socket)	
			if not data then
				break
			end
			self._dev:dump_comm('SOCKET-IN', data)
			self._socket_recv = self._socket_recv + string.len(data)

			if self._port then
				self._serial_sent = self._serial_sent + string.len(data)
				self._dev:dump_comm('SERIAL-OUT', data)
				self._port:write(data)
			end
		end
	end

	if self._socket then
		local to_close = self._socket
		self._socket = nil
		self._socket_sent = 0
		self._socket_recv = 0
		self._socket_peer = ''
		socket.close(to_close)
		--- 
		self:start_reconnect()
	end
end

function app:start_reconnect()
	if self._socket then
		local to_close = self._socket
		self._socket = nil
		socket.close(to_close)
	end
	--- only reconnect if tcp_client mode
	if socket_type == 'tcp_client' then
		self._sys:timeout(100, function()
			self:connect_proc()
		end)
	end
end

function app:start_socket()
	local socket_type = self._conf.socket_type
	if socket_type == 'tcp_client' then
		local conf = self._conf.tcp_client
		local sock, err = socket.open(conf.host, conf.port)
		if not sock then
			return nil, string.format("Cannot connect to %s:%d. err: %s", conf.host, conf.port, err or "")
		end

		if conf.nodelay then
			socketdriver.nodelay(sock)
		end

		self._socket = sock
		self._socket_peer = cjson.encode({
			host = conf.host,
			port = conf.port,
		})
		return true
	end
	if socket_type == 'tcp_server' then
		local conf = self._conf.tcp_server
		local sock, err = socket.listen(conf.host, conf.port)
		if not sock then
			return nil, string.format("Cannot listen on %s:%d. err: %s", conf.host, conf.port, err or "")
		end
		self._server_socket = sock
		socket.start(sock, function(fd, addr)
			self._log:info(string.format("New connection (fd = %d, %s)",fd, addr))
			if conf.nodelay then
				socketdriver.nodelay(fd)
			end

			local to_close = self._socket
			socket.start(fd)
			self._socket = fd
			self._socket_peer = cjson.encode({
				host = conf.host,
				port = conf.port,
			})
			if to_close then
				self._log:warning(string.format("Previous socket closing, fd = %d", to_close))
				socket.close(to_close)
			end
		end)
		return true
	end

	if socket_type == 'udp_server' then
	end
	if socket_type == 'udp_client' then
	end
	return false, "Unknown Socket Type"
end

--- 应用退出函数
function app:on_close(reason)
	if self._socket then
		local to_close = self._socket
		self._socket = nil
		socket.close(to_close)
	end
	if self._server_socket then
		local to_close = self._server_socket
		self._server_socket = nil
		socket.close(to_close)
	end
	if self._port then
		local to_close = self._port
		self._port = nil
		to_close:close(reason)
	end
end

--- 应用运行入口
function app:on_run(tms)
	self._dev:set_input_prop('serial_sent', 'value', self._serial_sent)
	self._dev:set_input_prop('serial_recv', 'value', self._serial_recv)
	self._dev:set_input_prop('socket_sent', 'value', self._socket_sent)
	self._dev:set_input_prop('socket_recv', 'value', self._socket_recv)
	self._dev:set_input_prop('serial_peer', 'value', self._socket and self._socket_peer or '')
	return 1000 --下一采集周期为1秒
end

--- 返回应用对象
return app

