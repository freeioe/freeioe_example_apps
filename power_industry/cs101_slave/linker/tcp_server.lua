local class = require 'middleclass'
local skynet = require 'skynet'
local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'

local tcp_server_linker = class("LUA_APP_LINKER_TCP_SERVER_CLASS")

--- 
function tcp_server_linker:initialize(linker, opt, log)
	self._linker = linker
	self._opt = opt
	self._log = log
end

function tcp_server_linker:write(raw)
	if self._socket then
		return socket.write(self._socket, raw)
	end
	return nil, "Connection closed!!!"
end

function tcp_server_linker:watch()
	while self._server_socket do
		while self._server_socket and not self._socket do
			skynet.sleep(10)
		end
		if not self._server_socket then
			break
		end

		while self._socket and self._server_socket do
			local data, err = socket.read(self._socket)	
			if not data then
				skynet.error("Client socket disconnected", err)
				break
			end
			self._linker:on_recv(data)
		end

		if self._socket then
			local to_close = self._socket
			self._socket = nil
			socket.close(to_close)
			self._linker:on_disconnected()
		end
	end
end

function tcp_server_linker:open()
	local conf = self._opt
	self._log:info(string.format("Listen on %s:%d", conf.host, conf.port))
	local sock, err = socket.listen(conf.host, conf.port)
	if not sock then
		local err = string.format("Cannot listen on %s:%d. err: %s", conf.host, conf.port, err or "")
		self._log:error(err)
		return nil, err
	end
	self._server_socket = sock
	socket.start(sock, function(fd, addr)
		skynet.error(string.format("New connection (fd = %d, %s)",fd, addr))
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
			skynet.error(string.format("Previous socket closing, fd = %d", to_close))
			socket.close(to_close)
			self._linker:on_disconnected()
		end

		self._linker:on_connected()
	end)

	return true
end

function tcp_server_linker:close()
	if self._socket then
		local to_close = self._socket
		self._socket = nil
		socket.close(to_close)
		self._linker:on_disconnected()
	end
	if self._server_socket then
		local to_close = self._server_socket
		self._server_socket = nil
		socket.close(to_close)
	end
end

return tcp_server_linker 
