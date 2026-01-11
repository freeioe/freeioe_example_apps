local serial = require 'serialdriver'
local basexx = require 'basexx'
local base = require 'app.base'
--local chk_sum = require 'hasings.sum16'
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
		conf.ports = {
			{ port = 8080 },
			{ port = 8082 },
			{ port = 8084 },
			{ port = 8086 },
		}
	end

	--- 增加设备实例
	local inputs = {}
	local vals = {}
	for i = 1, 8 do
		vals[i] = 0 -- default is 0
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
	self._dev = self._api:add_device(sn, meta, inputs, outputs)
	sys:fork(function()
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
	end)

	return true
end

--- 应用退出函数
function app:on_close(reason)
	self._closed = true
	if self._conn then
		local to_close = self._conn
		self._conn = nil
		websocket.close(to_close)
	end
	return true
end

--- 应用运行入口
function app:on_run(tms)
	local log = self:log_api()
	if self._conn then
		if self._hb_time then
			if (ioe.time() - self._hb_time) >= (self._ping_interval / 1000) then
				websocket.write(self._conn, '3', text, 1) -- heartbeat
				self._hb_time =  ioe.time()
			end
		end
		local resp, close_reason = websocket.read(self._conn)
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
				self:on_socketio_pt2(json)
			elseif pt == 40 then
				self:on_socketio_sid(json)
			elseif pt == 42 then
				self:on_socketio_data(json)
			else
				log:warning("Unknown Packet Type:", pt)
			end
		else
			self._conn = nil
			self._hb_time = nil
			log:warning("Connection closed. reason:", close_reason)
			-- TODO: invalid data???
		end
	end
::RUN_END::
	return 0
end

function app:on_socketio_open(json)
	if self._conn then
		websocket.write(self._conn, '40', text, 0)
		local data = cjson.decode(json)
		self._hb_time = ioe.time() - 1
		self._ping_interval = data.pingInterval
		self._ping_timeout = data.pingTimeout
	end
end

function app:on_socketio_sid(json)
end

function app:on_socketio_pt2(json)
	self:log_api():warning("Received PT2")
	websocket.write(self._conn, '3', text, 1) -- heartbeat
end


function app:on_socketio_data(json)
	local log = self:log_api()
	local data, err = cjson.decode(json)
	if not data or #data ~= 2 or data[1] ~= 'sm' then
		log:error("JSON decode error:", err)
		return
	end
	local t = {}
	for d in string.gmatch(data[2], '([^,]+)') do
		t[#t + 1] = tonumber(d)
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

