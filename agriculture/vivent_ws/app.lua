local base = require 'app.base'
local cjson = require 'cjson.safe'
local websocket = require 'http.websocket'
local ioe = require 'ioe'

local app = base:subclass("AGRI_VIVENT_WS_APP")
app.static.API_VER = 10

function app:on_init()
	self._ping_interval = 25000 -- ms
	self._ping_timeout = 5000 -- ms
end

--- 应用启动函数
function app:on_start()
	local conf = self:app_conf()
	local log = self:log_api()
	local sys = self:sys_api()

	--- 生成设备唯一序列号
	local sys_id = sys:id()

	if ioe.developer_mode() ~= 0 then
		conf.proto = conf.proto or 'ws'
		conf.sn = conf.sn or self._name
		conf.ip = conf.ip or '192.168.0.1'
	end

	if not conf.prots or #conf.ports == 0 then
		conf.ports = {
			{ port = 8080 },
			{ port = 8082 },
			{ port = 8084 },
			{ port = 8086 },
		}
	end

	--- 增加设备实例
	local inputs = {}
	for i = 1, 8 do
		table.insert(inputs, {
			name = "chn_"..i,
			desc = "通道#"..i,
			vt = "float"
		})
	end

	local meta = self._api:default_meta()
	meta.name = conf.name or "ViVent_PhytlSigns8"
	meta.inst = self._name
	meta.description = meta.name .. "模块"

	local sn = sys_id.."."..conf.sn
	self._dev = self._api:add_device(sn, meta, inputs)

	-- Start socket connection proc
	sys:fork(self.ws_socket_proc, self, conf)

	return true
end

function app:ws_socket_proc(conf)
	local log = self:log_api()
	local sys = self:sys_api()
	local cur_port = nil
	local cur_index = 0
	while not self._closed do
		if not self._conn then
			local port = cur_port
			if not port then
				cur_index = cur_index % #conf.ports + 1
				port = assert(conf.ports[cur_index]).port
			end
			-- /socket.io//?EIO=4&transport=websocket&EIO=4
			local url = string.format("%s://%s:%d/socket.io//?EIO=4&transport=websocket&EIO=4", conf.proto, conf.ip, port)
			local ok, conn = pcall(websocket.connect, url)
			if ok then
				self._conn = conn
				cur_port = port
				log:info("Connected to", url)
				-- websocket.ping(conn)
			else
				log:warning("Failed to connect to ", url, 'error ', conn)
			end
		end
		sys:sleep(1000)
	end
end

--- 应用退出函数
function app:on_close(reason)
	self._closed = true
	self:on_ws_close()
	return true
end

function app:on_ws_close()
	if self._conn then
		local to_close = self._conn
		self._conn = nil
		websocket.close(to_close)
	end
	self._hb_time = nil
end

--- 应用运行入口
function app:on_run(tms)
	local log = self:log_api()
	if self._conn then
		if self._hb_time then
			if (ioe.time() - self._hb_time) >= (self._ping_interval / 1000) then
				self._dev:dump_comm("OUT", '3')
				local r, resp = pcall(websocket.write, self._conn, '3', 'text', 1) -- heartbeat
				self._hb_time =  ioe.time()
				if not r then
					log:warning("Connection closed. reason:", resp)
					self:on_ws_close()
					return 1000;
				end
			end
		end
		local r, resp, close_reason = pcall(websocket.read, self._conn)
		if not r then
			log:warning("Connection closed. reason:", resp)
			self:on_ws_close()
			return 1000;
		end
		if resp then
			self._dev:dump_comm("IN", resp)
			local pt, json = string.match(resp, '^(%d+)(.*)')
			pt = tonumber(pt)
			if not pt then
				log:warning("Unknown MSG:", resp)
				goto RUN_END
			end
			if pt == 0 then
				self:on_socketio_open(json)
			elseif pt == 2 then
				self:on_socketio_pt2()
			elseif pt == 40 then
				self:on_socketio_sid()
			elseif pt == 42 then
				self:on_socketio_data(json)
			else
				log:warning("Unknown Packet Type:", pt)
			end
		else
			log:warning("Connection closed. reason:", close_reason)
			self:on_ws_close()
			return 1000;
		end
	end
::RUN_END::
	return 0
end

function app:on_socketio_open(json)
	if self._conn then
		self._dev:dump_comm("OUT", '40')
		local r, resp = pcall(websocket.write, self._conn, '40', 'text', 0)
		if not r then
			return self:on_ws_close()
		end
		local data, err = cjson.decode(json)
		if not data then
			local log = self:log_api()
			log:error("on_socketio_open, JSON decode error:", err)
			return
		end

		self._hb_time = ioe.time() - 1
		self._ping_interval = data.pingInterval
		self._ping_timeout = data.pingTimeout
	end
end

function app:on_socketio_sid()
end

function app:on_socketio_pt2()
	self:log_api():warning("Received PT2")
	self._dev:dump_comm("OUT", '3')
	local r, resp = pcall(websocket.write, self._conn, '3', 'text', 1) -- heartbeat
	if not r then
		return self:on_ws_close()
	end
end


function app:on_socketio_data(json)
	local log = self:log_api()
	local data, err = cjson.decode(json)
	if not data or #data ~= 2 or data[1] ~= 'sm' then
		log:error("on_socketio_data, JSON decode error:", err)
		return
	end
	local t = {}
	for d in string.gmatch(data[2], '([^,]+)') do
		t[#t + 1] = tonumber(d)
	end
	if t[1] == nil then
		log:error("on_socketio_data, incorrect data:", data[2], json)

		local data = { data = data, json = json, time=os.date() }
		self._dev:fire_event(event.LEVEL_ERROR, event.EVENT_APP, 'Data Error Event', data)
		return
	end
	-- print(#t)
	local tm = t[1] / 1000 -- MS
	-- print(tm)
	for i, v in ipairs(t) do
		if i > 1 then
			self._dev:set_input_prop("chn_"..(i - 1), 'value', v, tm, 0)
		end
	end
end

--- 返回应用对象
return app

