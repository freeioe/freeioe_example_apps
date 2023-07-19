local class = require 'middleclass'
local skynet = require 'skynet'
local socket = require 'skynet.socket'
local socketdriver = require 'skynet.socketdriver'

local tcp_client_linker = class("LUA_APP_LINKER_TCP_CLIENT_CLASS")

--- 
function tcp_client_linker:initialize(linker, opt, log)
	self._linker = linker
	self._opt = opt
	self._log = log
end

function tcp_client_linker:write(raw)
	if self._socket then
		return socket.write(self._socket, raw)
	end
	return nil, "Connection closed!!!"
end

function tcp_client_linker:open()
	local conf = self._opt
	local conf = self._opt.tcp
	self._log:info(string.format("Connecting to %s:%d", conf.host, conf.port))
	local sock, err = socket.open(conf.host, conf.port)
	if not sock then
		local err = string.format("Cannot connect to %s:%d. err: %s", conf.host, conf.port, err or "")
		self._log:error(err)
		return nil, err
	end
	self._log:notice(string.format("Connected to %s:%d", conf.host, conf.port))

	if conf.nodelay then
		socketdriver.nodelay(sock)
	end

	self._socket = sock
	self._linker:on_connected()

	return true
end

function tcp_client_linker:watch()
	while self._socket and not self._closing do
		local data, err = socket.read(self._socket)	
		if not data then
			self._log:error("Socket disconnected", err)
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


function tcp_client_linker:close()
	if self._socket then
		socket.close(self._socket)
		self._socket = nil
		self._linker:on_disconnected()
	end
end

return tcp_client_linker 
