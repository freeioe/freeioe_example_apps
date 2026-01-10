local serial = require 'serialdriver'
local basexx = require 'basexx'
local base = require 'app.base'
local chk_sum = require 'hasings.sum16'
local websocket = require 'http.websocket'
local ioe = require 'ioe'

local app = base:subclass("AGRI_FLYBIRD_APP")
app.static.API_VER = 10

function app:on_init()
end

--- 应用启动函数
function app:on_start()
	local conf = self:app_conf()
	local log = self:log_api()
	local sys = self:sys_api()

	--- 生成设备唯一序列号
	local sys_id = sys:id()

	if ioe.developer_mode() ~= 0 then
		conf.sn = conf.sn or self._name
		conf.ip = conf.ip or '192.168.254.1'
		conf.ports = {
			{ port = 8080 },
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
	meta.name = conf.name or "FlyBird"
	meta.inst = self._name
	meta.description = conf.name .. "模块"

	local sn = sys_id.."."..conf.sn
	self._dev = self._api:add_device(sn, meta, inputs, outputs)
	sys:fork(function()
		local cur_port = nil
		local cur_index = 0
		while not self._closed do
			if not self._conn then
				local port = cur_port
				if not port then
					cur_index = (cur_index + 1) % #conf.ports
					port = assert(conf.ports[cur_index]).port
				end
				local url = string.format("%s://%s:%d/socket.io/", conf.proto, conf.ip, port)
				local ok, conn = pcall(websocket.connect, url)
				if ok then
					self._conn = conn
					cur_port = port
					log:info("Connected to %s", url)
					websocket.write(conn, 'hello world')
				else
					log:warn("Failed to connect to %s: %s", url, conn)
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
	if self._conn then
		local resp, close_reason = websocket.read(self._conn)
		if resp then
			self._dev:sump_comm("IN", data)
			local t = {}
			for d in string.gmatch(resp, '([^,]+)') do
				t[#t + 1] = tonumber(d)
			end
			local tm = t[1] * 1000 -- MS
			for i, v in iparis(t) do
				if i > 1 then
					self._dev:set_input_prop(v.name, 'value', t[i], tm, 0)
				end
			end
		else
			self._conn = nil
			self:log_api():warn("Connection closed: %s", close_reason)
			-- TODO: invalid data???
		end
	end
	return 0
end

--- 返回应用对象
return app

