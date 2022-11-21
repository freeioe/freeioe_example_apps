local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'
local serial = require 'serialdriver'
local basexx = require 'basexx'
local cjson = require 'cjson.safe'
local sapp = require 'app.base'

local app = sapp:subclass("freeioe.other.dtu_m")
app.static.API_VER = 10

function app:on_init()
	self._serial_sent = 0
	self._serial_recv = 0
	self._socket_sent = 0
	self._socket_recv = 0
	self._peers = {}
	self._send_buf = {}
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
		{name="socket_peer", desc="Socket peer list", vt="string"}
	}

	local meta = self._api:default_meta()
	meta.name = "DTU Multi"
	meta.inst = self._name
	meta.description = "DTU Multi Meta"

	local conf = self:app_conf()
	self._kick_same_ip = conf.kick_same_ip

	self._dev = self._api:add_device(sn, meta, inputs)
	self._closing = false

	self._sys:timeout(0, function()
		self:serial_proc()
	end)

	self._sys:timeout(10, function()
		self:fire_data_proc()
	end)
	self._sys:timeout(10, function()
		self:listen_proc()
	end)

	return true
end

function app:serial_proc()
	local conf = self:app_conf()

	local opt = assert(conf.serial)
	local port = serial:new(opt.port,
							opt.baudrate or 9600,
							opt.data_bits or 8,
							opt.parity or 'NONE',
							opt.stop_bits or 1,
							opt.flow_control or "OFF")

	local r, err = port:open()
	if not r then
		self._log:warning("Failed open port, error: "..err)

		if not self._closing then
			self._sys:timeout(10000, function()
				return self:serial_proc()
			end)
		end
		return
	end

	port:start(function(data, err)
		-- Recevied Data here
		if data then
			self._dev:dump_comm('SERIAL-IN', data)
			self._serial_recv = self._serial_recv + string.len(data)

			--self._log:debug("Recevied data", basexx.to_hex(data))
			table.insert(self._send_buf, data)

			if self._wait_buf then
				self._sys:wakeup(self._wait_buf)
			end
		else
			--- Just return with log the error
			if self._closing then
				return
			end

			print(err)
			self._log:error(err)

			-- Close serial first
			if self._port then
				local to_close = self._port
				self._port = nil
				to_close:close(reason)
			end

			self._sys:timeout(0, function()
				return self:serial_proc()
			end)
		end
	end)
	self._port = port
end

function app:listen_proc()
	self._log:info("Start socket connection", err)

	while not self._closing do
		local r, err = self:start_listen()
		if r then
			break
		end

		self._sys:sleep(3000)

		self._log:debug("Wait for restart listen socket", sleep_gap)
	end

	assert(self._server_socket)
end

function app:watch_client_socket(sock, addr)
	while true do
		local data, err = socket.read(sock)	
		if not data then
			self._log:info("Socket disconnected", err)
			break
		end
		self._dev:dump_comm('SOCKET-IN['..addr..']', data)
		self._socket_recv = self._socket_recv + string.len(data)

		if self._port then
			self._serial_sent = self._serial_sent + string.len(data)
			self._dev:dump_comm('SERIAL-OUT', data)
			self._port:write(data)
		end
	end

	self._peers[sock] = nil
end

function app:start_listen()
	local c = self:app_conf()
	local conf = assert(c.tcp_server)

	self._log:info(string.format("Listen on %s:%d", conf.host, conf.port))
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

		assert(not self._peers[fd])
		local to_close_by_host = nil

		--- Bind socket to current service
		socket.start(fd)

		local host, port = string.match(addr, "^(.+):(%d+)$")
		self._peers[fd] = {
			addr = addr
		}

		if host and port then
			self._peers[fd] = {
				host = host,
				port = port,
				addr = addr
			}

			if self._kick_same_ip then
				for k, v in pairs(self._peers) do
					if v.host == host then
						to_close_by_host = k
					end
				end
			end
		end

		socket.onclose(function(fd)
			self._peers[fd] = nil
		end)

		self._sys:fork(function()
			self:watch_client_socket(fd, addr)
		end)

		if to_close_by_host then
			self._log:warning(string.format("Previous socket closing, fd = %d", to_close))
			socket.close(to_close_by_host)
		end
	end)

	--- When listen socket closed then restart it
	socket.onclose(sock, function()
		self._log:warning("Listen socket closed!")
		self._server_socket = nil

		if not self._closing then
			for sock, peer in pairs(self._peers) do
				socket.close(sock)
			end

			self._sys:timeout(1000, function()
				self:listen_proc(fd)
			end)
		end
	end)

	return true
end

function app:fire_data_proc()
	while not self._closing do
		if #self._send_buf == 0 then
			self._wait_buf = {}
			self._sys:wait(self._wait_buf, 10000)
			self._wait_buf = nil
		end

		if self._closing then
			break
		end

		--- Swap buffer
		local buf = self._send_buf
		self._send_buf = {}

		local data = table.concat(buf)
		local added = false
		for fd, peer in pairs(self._peers) do
			if not added then
				added = true
				self._socket_sent = self._socket_sent + string.len(data)
			end

			self._dev:dump_comm('SOCKET-OUT['..peer.addr..']', data)
			local r, err = pcall(socket.write, fd, data)
			if not r then
				self._log:error("Write to client "..peer.addr.." error:"..err)
			end
		end
	end
	assert(self._closing)
	self._log:info("Fire data proc quit!")
end

--- 应用退出函数
function app:on_close(reason)
	self._closing = true

	-- Close serial first
	if self._port then
		local to_close = self._port
		self._port = nil
		to_close:close(reason)
	end

	--- Close linsten socket
	if self._server_socket then
		socket.close(self._server_socket)
	end

	-- Quit the fire_data_proc
	if self._wait_buf then
		self._sys:wakeup(self._wait_buf)
	end

	while self._server_socket do
		self._log:warning("Wait for listen socket closed")
		self._sys:sleep(1000)
	end

	for fd, peer in pairs(self._peers) do
		self._log:warning("Closing client", peer.addr)
		socket.close(fd)
	end

	return true
end

--- 应用运行入口
function app:on_run(tms)
	self._dev:set_input_prop('serial_sent', 'value', self._serial_sent)
	self._dev:set_input_prop('serial_recv', 'value', self._serial_recv)
	self._dev:set_input_prop('socket_sent', 'value', self._socket_sent)
	self._dev:set_input_prop('socket_recv', 'value', self._socket_recv)
	local data = {}
	for k, v in pairs(self._peers) do
		table.insert(data, v)
	end

	local str, err = cjson.encode(data)
	if str then
		self._dev:set_input_prop('socket_peer', 'value', str)
	else
		self._log:error(err)
	end

	return 1000 --下一采集周期为1秒
end

--- 返回应用对象
return app

