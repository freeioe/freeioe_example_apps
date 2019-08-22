local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local serial = require 'serialdriver'
local cjson = require 'cjson.safe'
local sapp = require 'app.base'
local sysinfo = require 'utils.sysinfo'
local summation = require 'summation'
local modbus_rtu = require 'modbus.apdu.rtu'
local modbus_ascii = require 'modbus.apdu.ascii'
local modbus_tcp = require 'modbus.apdu.tcp'
local basexx = require 'basexx'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = sapp:subclass("MODBUS_GATEWAY_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 5

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:on_init()
	self._log:debug("Port example application initlized")

	self._socket_peer = ''
	self._stat_sum = summation:new({
		file = true,
		save_span = 60 * 10,
		key = self._name .. '_port_stat',
		span = 'day',
		path = sysinfo.data_dir()
	})
	self._key_map = {}
end

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._name

	--- 增加设备实例
	local inputs = {
		{name="serial_option", desc="Serial option information", vt="string"},
		{name="socket_peer", desc="Socket peer information", vt="string"},
	}

	local meta = self._api:default_meta()
	meta.name = "ModbusGateway"
	meta.inst = self._name
	meta.description = "Modbus Gateway Application"

	self._dev = self._api:add_device(sn, meta, inputs)
	self._socket_stat = self._dev:stat('socket')
	self._serial_stat = self._dev:stat('serial')

	self._serial_apdu = modbus_rtu:new() -- modbus_ascii:new()
	self._socket_apdu = modbus_tcp:new()

	local conf = self._conf
	conf.serial = conf.serial or {}
	self._serial_opt = {
		port = conf.serial.port or '/tmp/ttyS1',
		baudrate = conf.serial.baudrate or 9600,
		data_bits = conf.serial.data_bits or 8,
		parity = conf.serial.parity or 'NONE',
		stop_bits = conf.serial.stop_bits or 1,
		flow_control = conf.serial.flow_control or 'OFF',
	}
	self._serial_opt_str = cjson.encode(self._serial_opt)

	local r, err = self:serial_proc()
	if not r then
		return nil, err
	end

	self._sys:timeout(10, function()
		self:listen_proc()
	end)

	return true
end

function app:serial_proc()
	local opt = self._serial_opt
	local port = serial:new(opt.port, opt.baudrate, opt.data_bits, opt.parity, opt.stop_bits, opt.flow_control)

	local r, err = port:open()
	if not r then
		self._serial_stat:set('status', -1)
		self._log:warning("Failed open port, error: "..err)
		return nil, err
	else
		self._serial_stat:set('status', 0)
	end

	port:start(function(data, err)
		-- Recevied Data here
		if data then
			self._dev:dump_comm('SERIAL-IN', data)
			self._stat_sum:add('serial_recv', string.len(data))

			self._log:debug("Serial Recv", basexx.to_hex(data))
			self._serial_apdu:append(data)
			self._serial_apdu:process(function(key, unit, pdu)
				if self._socket then
					local from_key = self._key_map[key]
					local apdu, key = self._socket_apdu:pack(unit, pdu, from_key)
					assert(key == from_key)
					self._dev:dump_comm('SOCKET-OUT', apdu)
					socket.write(self._socket, apdu)
					self._stat_sum:add('socket_send', string.len(apdu))
				else
					--- TODO:
				end
			end)
		else
			self._log:error(err)
			self._serial_state:set('status', -1)
			self._port = nil
			local r, err = pcall(port.close, port, 'error close')

			self._sys:timeout(100, function()
				local connect_gap = 1000
				while true do
					self._sys:sleep(connect_gap)
					local r, err = self:serial_proc()
					if r then
						break
					end

					connect_gap = connect_gap * 2
					if connect_gap > 64 * 1000 then
						connect_gap = 1000
					end
					self._log:debug("Waiting for open serial port", connect_gap)
				end
			end)
		end
	end)
	self._port = port

	return true
end

function app:listen_proc()
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
		self._log:debug("Wait for retart connection", connect_gap)
	end

	self:watch_server_socket()
end

function app:watch_server_socket()
	while self._server_socket do
		while self._server_socket and not self._socket do
			self._sys:sleep(50)
		end
		if not self._server_socket then
			break
		end

		while self._socket and self._server_socket do
			local data, err = socket.read(self._socket)	
			if not data then
				self._log:info("Client socket disconnected", err)
				break
			end
			self._log:debug("Socket Recv", basexx.to_hex(data))
			self._dev:dump_comm('SOCKET-IN', data)
			self._stat_sum:add('socket_recv', string.len(data))

			self._socket_apdu:append(data)
			self._socket_apdu:process(function(key, unit, pdu)
				if self._port then
					local apdu, new_key = self._serial_apdu:pack(unit, pdu)
					self._key_map[new_key] = key

					self._stat_sum:add('serial_send', string.len(apdu))
					self._dev:dump_comm('SERIAL-OUT', apdu)
					self._port:write(apdu)
				end
			end)
		end

		if self._socket then
			local to_close = self._socket
			self._socket = nil
			self._socket_peer = ''
			socket.close(to_close)
			--- 
		end
	end

	if not self._server_socket then
		self._sys:timeout(100, function()
			self:listen_proc()
		end)
	end
end

function app:start_connect()
	self._socket_stat:set('status', 1)
	local socket_type = self._conf.socket_type
	if socket_type == 'tcp_server' then
		local conf = self._conf.tcp_server or {
			host = '0.0.0.0',
			port = '2502'
		}
		self._log:info(string.format("Listen on %s:%d", conf.host, conf.port))
		local sock, err = socket.listen(conf.host, conf.port)
		if not sock then
			self._socket_stat:set('status', -1)
			return nil, string.format("Cannot listen on %s:%d. err: %s", conf.host, conf.port, err or "")
		else
			self._socket_stat:set('status', 0)
		end
		self._server_socket = sock
		socket.start(sock, function(fd, addr)
			self._log:info(string.format("New connection (fd = %d, %s)",fd, addr))
			--- TODO: Limit client ip/host

			if conf.nodelay then
				socketdriver.nodelay(fd)
			end

			local to_close = self._socket
			socket.start(fd)
			self._socket = fd

			local host, port = string.match(addr, "^(.+):(%d+)$")
			if host and port then
				self._socket_peer = cjson.encode({
					host = host,
					port = port,
				})
			else
				self._socket_peer = addr
			end
			if to_close then
				self._log:warning(string.format("Previous socket closing, fd = %d", to_close))
				socket.close(to_close)
			end
		end)
		return true
	end

	if socket_type == 'udp_server' then
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
		self._socket_stat:set('status', 0xFFFF)
		local to_close = self._server_socket
		self._server_socket = nil
		socket.close(to_close)
	end
	if self._port then
		self._serial_stat:set('status', 0xFFFF)
		local to_close = self._port
		self._port = nil
		to_close:close(reason)
	end
end

--- 应用运行入口
function app:on_run(tms)
	self._serial_stat:set('bytes_in', self._stat_sum:get('serial_recv'))
	self._serial_stat:set('bytes_out', self._stat_sum:get('serial_send'))
	self._socket_stat:set('bytes_in', self._stat_sum:get('socket_recv'))
	self._socket_stat:set('bytes_out', self._stat_sum:get('socket_send'))

	self._dev:set_input_prop('socket_peer', 'value', self._socket and self._socket_peer or '')
	self._dev:set_input_prop('serial_option', 'value', self._serial_opt_str)

	return 1000 --下一采集周期为1秒
end

--- 返回应用对象
return app

