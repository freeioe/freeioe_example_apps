local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'
local sha1 = require 'hashings.sha1'
local hmac = require 'hashings.hmac'
local ioe = require 'ioe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = mqtt_app:subclass("THINGSROOT_MQTT_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.static.API_VER = 8

local mqtt_secret = "VEhJTkdTUk9PVAo="

function app:to_mqtt_app_conf(conf)
	conf.mqtt = conf.mqtt or {}
	local new_conf = {
		--- mqtt
		client_id = conf.mqtt.client_id and conf.mqtt.client_id ~= '' and conf.mqtt.client_id or nil,
		username = conf.mqtt.username and conf.mqtt.username ~= '' and conf.mqtt.username or nil,
		password = conf.mqtt.password and conf.mqtt.password ~= '' and conf.mqtt.password or nil,
		server = conf.mqtt.server or '172.30.11.199',
		port = conf.mqtt.port,
		enable_tls = conf.mqtt.enable_tls,
		tls_insecure = conf.mqtt.tls_insecure ~= nil and conf.mqtt.tls_insecure or false,
		tls_cert = conf.tls_cert_path,
		tls_client_cert = conf.tls_client_cert_path,
		tls_client_key = conf.tls_client_key_path,
	}
	for k, v in pairs(conf.options or {}) do
		new_conf[k] = v
	end
	if conf.has_options_ex == 'yes' then
		self._disable_data = conf.options_ex.disable_data
		self._disable_event = conf.options_ex.disable_event
		self._disable_devices = conf.options_ex.disable_devices
		self._disable_data_em = conf.options_ex.disable_data_em
		self._disable_output = conf.options_ex.disable_output
		self._disable_command = conf.options_ex.disable_command
		self._disable_compress = conf.options_ex.disable_compress
	end
	self._disable_apps = true --- application list not supported!!!!
	self._disable_stat = true --- statiticsis not supported!!!

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

local function valid_device_sn(sn)
	--return nil == string.find(sn, '%s')
	return nil == string.find(sn, "[^%w_%-%.]")
end

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	self._prv_conf = conf
	self._sys = sys
	local log = sys:logger()

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

	self._allowed_devicess = {}
	for _, v in ipairs(conf.devs or {}) do
		if not valid_device_sn(v.sn) then
			log:error("Invalid device SN", v.sn)
		end

		if v.sn and string.len(v.sn) > 0 then
			self._allowed_devicess[v.sn] = true
		else
			log:warning("Device SN missing in conf.devs item")
		end
	end

	local sys_id = sys:id()

	local mqtt_conf = self:to_mqtt_app_conf(conf)
	if not mqtt_conf.username then
		mqtt_conf.username = "dev="..sys_id.."|time="..os.time()
		mqtt_conf.password = hmac:new(sha1, mqtt_secret, sys_id):hexdigest()
	end
	if not mqtt_conf.client_id then
		mqtt_conf.client_id = sys_id
	end
	--[[
	--- DEBUG
	self._disable_compress = true
	self._allowed_devicess[sys_id] = true
	]]--

	--- 基础类初始化
	mqtt_app.initialize(self, name, sys, mqtt_conf)

	self._mqtt_id = mqtt_conf.client_id
end

function app:pack_key(app_src, device_sn, ...)
	-- if data upload disabled
	if self._disable_data then
		return
	end

	--- if deivce not in allowed list
	if not self._allowed_devicess[device_sn] then
		return
	end

	--- using the base pack key
	return mqtt_app.pack_key(self, app_src, device_sn, ...)
end

function app:on_publish_data(key, value, timestamp, quality)
	--local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	local msg = {{ key, value, timestamp, quality}}
	return self:publish(self._mqtt_id.."/data", cjson.encode(msg), 0, false)
end

function app:on_publish_data_em(key, value, timestamp, quality)
	if self._disable_data_em then
		return
	end

	return self:on_publish_data(key, value, timestamp, quality)
end

function app:on_publish_data_list(val_list)
    local data=cjson.encode(val_list)
    if self._disable_compress then
		return self:publish(self._mqtt_id.."/data", data, 0, false)
	else
        data = self:compress(data)
		return self:publish(self._mqtt_id.."/data_gz", data, 0, false)
    end
end

function app:on_publish_cached_data_list(val_list)
	local data=cjson.encode(val_list)
    if not self._disable_compress then
		return self:publish(self._mqtt_id.."/cached_data", data, 0, false)
	else
        data = self:compress(data)
		return self:publish(self._mqtt_id.."/cached_data_gz", data, 0, false)
    end
end

function app:on_event(app, sn, level, type_, info, data, timestamp)
	if self._disable_event then
		return true
	end
	if not self._allowed_devicess[sn] then
		return true
	end

	local event = {
		level = level,
		['type'] = type_,
		info = info,
		data = data,
		app = app
	}
	return self:publish(self._mqtt_id.."/event", cjson.encode({sn, event, timestamp} ), 1, false)
end

--[[
function app:on_stat(app, sn, stat, prop, value, timestamp)
	if self._disable_stat then
		return true
	end

	local msg = {
		app = app,
		sn = sn,
		stat = stat,
		prop = prop,
		value = value,
		timestamp = timestamp,
	}
	return self:publish(self._mqtt_id.."/stat", cjson.encode(msg), 1, false)
end
]]--

function app:on_publish_devices(devices)
	if self._disable_devices then
		return true
	end
	local new_devices = {}
	for k, v in pairs(self._allowed_devicess) do
		if v then
			new_devices[k] = devices[k]
		end
	end

	local data, err = cjson.encode(new_devices)
	if not data then
		self._log:error("Devices data json encode failed", err)
		return false
	end

	if self._disable_compress then
		return self:publish(self._mqtt_id.."/devices", data, 1, true)
	else
		data = self:compress(data)
		return self:publish(self._mqtt_id.."/devices_gz", data, 1, true)
	end
end

function app:on_mqtt_connect_ok()
	local sub_topics = {}
	if not self._disable_output then
		table.insert(sub_topics, '/output/#')
	end
	if not self._disable_command then
		table.insert(sub_topics, '/command/#')
	end
	for _, v in ipairs(sub_topics) do
		self:subscribe(self._mqtt_id..v, 1)
	end
	return self:publish(self._mqtt_id.."/status", "ONLINE", 1, true)
end

function app:mqtt_will()
	return self._mqtt_id.."/status", "OFFLINE", 1, true
end

function app:on_mqtt_message(mid, topic, payload, qos, retained)
	local id, t, sub = topic:match('^([^/]+)/([^/]+)(.-)$')
	if id ~= self._mqtt_id and id ~= "ALL" then
		self._log:error("MQTT recevied incorrect topic message")
		return
	end
	local data, err = cjson.decode(payload)
	if not data then
		self._log:error("Decode JSON data failed", err)
		return
	end

	if t == 'output' then
		self:on_mqtt_output(string.sub(sub or '/', 2), data.id, data.data)
	elseif t == 'command' then
		self:on_mqtt_command(string.sub(sub or '/', 2), data.id, data.data)
	else
		self._log:error("MQTT recevied incorrect topic", t, sub)
	end
end

function app:on_mqtt_result(id, result, message)
	local data = {
		id = id,
		result = result,
		message = message,
		timestamp = ioe.time(),
		timestamp_str = os.date()
	}
	self:publish(self._mqtt_id..'/result/output', cjson.encode(data), 0, false)
end

function app:on_mqtt_output(topic, id, data)
	if self._disable_output then
		return self:on_mqtt_result(id, false, 'Device output disabled!')
	end
	if not self._allowed_devicess[data.device] then
		return self:on_mqtt_result(id, false, 'Device not allowed!')
	end

	local device, err = self._api:get_device(data.device)
	if not device then
		return self:on_mqtt_result(id, false, err or 'Device missing!')
	end

	local priv = {id = id, data = data}
	local r, err = device:set_output_prop(data.output, data.prop or 'value', data.value, ioe.time(), priv)
	if not r then
		self._log:error('Set output prop failed!', err)
		return self:on_mqtt_result(id, false, err or 'Set output prop failed')
	end
end

function app:on_output_result(app_src, priv, result, err)
	if not result then
		self._log:error('Set output prop failed!', err)
		return self:on_mqtt_result(priv.id, false, err or 'Set output prop failed')
	else
		return self:on_mqtt_result(priv.id, true, 'Set output prop done!!')
	end
end

function app:on_mqtt_command(topic, id, data)
	if self._disable_command then
		return self:on_mqtt_result(id, false, 'Device command disabled!')
	end
	if not self._allowed_devicess[data.device] then
		return self:on_mqtt_result(id, false, 'Device not allowed!')
	end

	local device, err = self._api:get_device(data.device)
	if not device then
		return self:on_mqtt_result(id, false, err or 'Device missing!')
	end

	local priv = {id = id, data = data}
	local r, err = device:send_command(data.cmd, data.param or {}, priv)
	if not r then
		self._log:error('Device command execute failed!', err)
		return self:on_mqtt_result(id, false, err or 'Device command execute failed!')
	end
end

function app:on_command_result(app_src, priv, result, err)
	if not result then
		self._log:error('Device command execute failed!', err)
		return self:on_mqtt_result(priv.id, false, err or 'Device command execute failed!')
	else
		return self:on_mqtt_result(priv.id, true, 'Device command execute done!!')
	end
end

--- 返回应用对象
return app
