local class = require 'middleclass'
local skynet = require 'skynet'
local serial = require 'serialdriver'

local serial_linker = class("LUA_APP_LINKER_SERIAL_CLASS")

--- 
-- opt
-- log
function serial_linker:initialize(linker, opt, log)
	self._linker = linker
	self._opt = opt
	self._log = log
end

function serial_linker:connected()
	return self._port ~= nil
end

--- Timeout: ms
function serial_linker:write(raw)
	if self._port then
		return self._port:write(raw)
	end
	return nil, "Connection closed!!!"
end

function serial_linker:open()
	local opt = self._opt
	local port = serial:new(opt.port, opt.baudrate or 9600, opt.data_bits or 8, opt.parity or 'NONE', opt.stop_bits or 1, opt.flow_control or "OFF")
	self._log:info("Open serial port:"..opt.port)
	local r, err = port:open()
	if not r then
		self._log:error("Failed open serial port:"..opt.port..", error: "..err)
		return nil, err
	end

	port:start(function(data, err)
		-- Recevied Data here
		if data then
			self._linker:on_recv(data)
		else
			self._log:error(err)
			port:close()
			self._port = nil
			self._linker:on_disconnected()
			if self._watch_wait then
				skynet.wakeup(self._watch_wait)
			end
		end
	end)

	self._port = port
	self._linker:on_connected()
	self._log:info("Open serial port:"..opt.port..' done!')
	return true
end

function serial_linker:watch()
	self._watch_wait = {}
	skynet.wait(self._watch_wait)
	self._watch_wait = nil
end

function serial_linker:close()
	if self._port then
		self._port:close()
		self._port = nil
		self._linker:on_disconnected()
	end
	if self._watch_wait then
		skynet.wakeup(self._watch_wait)
	end
end

return serial_linker 
