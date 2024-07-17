local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'
local sha1 = require 'hashings.sha1'
local hmac = require 'hashings.hmac'
local ioe = require 'ioe'
local csv_tpl = require 'csv_tpl'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = mqtt_app:subclass("LJ_ENERGY_MQTT_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.static.API_VER = 15

local mqtt_secret = "VEhJTkdTUk9PVAo="

function app:to_mqtt_app_conf(conf)
	conf.mqtt = conf.mqtt or {}
	conf.enable_data_cache = false
	local new_conf = {
		--- mqtt
		client_id = conf.mqtt.client_id and conf.mqtt.client_id ~= '' and conf.mqtt.client_id or nil,
		username = conf.mqtt.username and conf.mqtt.username ~= '' and conf.mqtt.username or nil,
		password = conf.mqtt.password and conf.mqtt.password ~= '' and conf.mqtt.password or nil,
		server = conf.mqtt.server or '60.205.126.52',
		port = conf.mqtt.port or 7001,
		enable_tls = conf.mqtt.enable_tls,
		tls_insecure = conf.mqtt.tls_insecure ~= nil and conf.mqtt.tls_insecure or false,
		tls_cert = conf.tls_cert_path,
		tls_client_cert = conf.tls_client_cert_path,
		tls_client_key = conf.tls_client_key_path,
		qos = true,
		period = 0,
	}
	for k, v in pairs(conf.options or {}) do
		new_conf[k] = v
	end

	return new_conf
end

function app:text2file(text, filename)
	if not text or string.len(text) == 0 then
		return nil
	end

	local full_path = self._sys:app_dir()..filename
	local f = assert(io.open(full_path, 'w+'))
	f:write(text)
	f:close()
	return filename
end

---
function app:initialize(name, sys, conf)
	local sys_id = sys:id()
	local mqtt_conf = self:to_mqtt_app_conf(conf)

	mqtt_conf.seq = mqtt_conf.seq or sys_id

	self._mqtt_id = mqtt_conf.client_id or sys_id

	return mqtt_app.initialize(self, name, sys, mqtt_conf)
end

---
-- 应用对象初始化函数
function app:on_start()
	local sys = self._sys
	local log = sys:logger()
	local conf = self._conf or {}

	conf.mqtt = conf.mqtt or {}
	--[[
	conf.mqtt = conf.mqtt or {
		username = 'viccom',
		password = 2623824,
		server = 'dongbala.top',
		port = 8883,
		enable_tls = true,
		tls_insecure = true
		tls_cert = [[-----BEGIN CERTIFICATE-----
MIICxjCCAa6gAwIBAgIJAJk1DbZBu8FDMA0GCSqGSIb3DQEBCwUAMBMxETAPBgNV
BAMMCE15VGVzdENBMB4XDTE3MTEwMjEzNDI0N1oXDTE5MTEwMjEzNDI0N1owEzER
MA8GA1UEAwwITXlUZXN0Q0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
AQDshDho6ef1JClDJ24peSsXdFnFO3xIB7+BSp1YPcOvmRECKUG0mLORw3hNm15m
8eGOn1iLGE/xKlaZ74/xjyq8f7qIGZCmvZj59m+eiJCAmy8SiUJZtSVoOlOzepJd
PoDgcBvDKA4ogZ3iJHMUNI3EdlD6nrKEJF2qe2JUrL0gv65uo2/N7XVNvE87Dk3J
83KyCAmeu+x+moS1ILnjs2DuPEGSxZqzf7IQMbXuNWJYAOZg9t4Fg0YjTiAaWw3G
JKAoMY4tI3JCqlvwGR4lH7kfk3WsD4ofGlFhxU4nEG0xgnJl8BcoJWD1A2RjGe1f
qCijqPSe93l2wt8OpbyHzwc7AgMBAAGjHTAbMAwGA1UdEwQFMAMBAf8wCwYDVR0P
BAQDAgEGMA0GCSqGSIb3DQEBCwUAA4IBAQAi+t5jBrMxFzoF76kyRd3riNDlWp0w
NCewkohBkwBHsQfHzSnc6c504jdyzkEiD42UcI8asPsJcsYrQ+Uo6OBn049u49Wn
zcSERVSVec1/TAPS/egFTU9QMWtPSAm8AEaQ6YYAuiwOLCcC+Cm/a3e3dWSRWt8o
LqKX6CWTlmKWe182MhFPpZYxZQLGapti4R4mb5QusUbc6tXbkcX82GjDPTOuAw7b
mWpzVd5xnlp7Vz+50u+YaAYUmCobg0hR/AuTrA4GDMlgzTnuZQhF6o8iVkypXOtS
Ufz6X3tVVErVVc7UUfzSnupHj1M2h4rzlQ3oqHoAEnXcJmV4f/Pf/6FW
-----END CERTIFICATE-----]]
--]]--

	-- TODO: tls_certs saving file
	conf.tls_cert_path = self:text2file(conf.mqtt.tls_cert, 'ca.crt')
	conf.tls_client_cert_path = self:text2file(conf.mqtt.client_cert, 'client_cert.crt')
	conf.tls_client_key_path = self:text2file(conf.mqtt.client_key, 'client_key.crt')

	csv_tpl.init(sys:app_dir())

	---获取设备序列号和应用配置
	local sys_id = sys:id()
	--- Mapping 
	local function map_dev_sn(sn)
		if sn == 'GW' then
			return sys_id
		end
		local sn = sn or 'GW'
		sn = string.gsub(sn, '^GW(%..*)$', sys_id..'%1')
		return sn
	end

	local tpl_id = conf.tpl
	local tpl_ver = conf.ver
	if conf.tpls and #conf.tpls >= 1 then
		tpl_id = conf.tpls[1].id
		tpl_ver = conf.tpls[1].ver
	end

	if tpl_id and tpl_ver then
		local capi = sys:conf_api(tpl_id)
		local data, err = capi:data(tpl_ver)
		if not data then
			log:error("Failed loading template from cloud!!!", err)
			return false
		end
		tpl_file = tpl_id..'_'..tpl_ver
	end

	if ioe.developer_mode() then
		tpl_file = 'test'
	end

	log:info("Loading template", tpl_file)
	local tpl, err = csv_tpl.load_tpl(tpl_file, function(...)
		log:error(...)
	end)
	if not tpl then
		return nil, err
	end

	for _, v in ipairs(tpl.props) do
		v.sn = map_dev_sn(v.sn)
	end
	self._tpl = tpl

	self._data_map = {}
	self._heartbeat_timeout = 0
	self._upload_timeout = 0

	return mqtt_app.on_start(self)
end

function app:pack_key(app_src, sn, input, prop)
	if prop ~= 'value' then
		return nil
	end
	-- print(sn, input, prop)

	local props = self._tpl.props

	for _, v in ipairs(props) do
		if v.sn == sn and v.tag == input then
			return sn..'/'..input
		end
	end
	return nil
end

function app:on_publish_data(key, value, timestamp, quality)
	local sn, input = string.match(key, '^([^/]+)/(.+)$')

	local props = self._tpl.props

	for _, v in ipairs(props) do
		if v.sn == sn and v.tag == input then
			self._data_map[v.name] = { value, timestamp, quality }
		end
	end

	-- return self:publish(self._mqtt_id.."/data", cjson.encode(msg), 0, false)
end

function app:on_publish_devices(devices)
	return true
end

function app:on_mqtt_connect_ok()
	self._connected = true
end

function app:on_mqtt_disconnect()
	self._connected = false
end

function app:on_mqtt_message(mid, topic, payload, qos, retained)
	self._log:error("MQTT recevied message", mid, topic, payload, qos, retained)
end

function app:on_run(tms)
	if not self._connected then
		return 1000
	end

	self:check_heartbeat()
	self:check_upload_data()

	return 1000
end

function app:check_heartbeat()
	if self._sys:time() > self._heartbeat_timeout  then
		self._heartbeat_timeout = self._sys:time() + 60
		
		local data = {
			seq = self._conf.seq,
			projectId = self._conf.prj_id,
			time = os.date('%F %T', math.floor(self._sys:time())),
			type = 0,
		}
		-- self._log:info('ping', cjson.encode(data))
		return self:publish("/energy/heart/ping/"..data.seq, cjson.encode(data), 0, false)
	end
end

function app:check_upload_data()
	if self._sys:time() > self._upload_timeout  then
		self._upload_timeout = self._sys:time() + (self._conf.cycle or 5000) // 1000
		
		local msg = {
			seq = self._conf.seq,
			projectId = self._conf.prj_id,
			total = 1,
			uploadTime = os.date('%F %T', math.floor(self._sys:time())),
			deviceId = self._conf.dev_id,
			['type'] = self._conf.m_id,
			state = 1,
		}

		local data = {}
		for k, v in pairs(self._data_map) do
			data[k] = v[1]
		end
		msg.val = data
		
		-- self._log:info('data', cjson.encode(msg))
		return self:publish("/energy/data/"..msg.seq, cjson.encode(msg), 0, false)
	end
end

--- 返回应用对象
return app
