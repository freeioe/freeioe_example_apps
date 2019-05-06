local cjson = require 'cjson.safe'
local aliyun_http = require 'aliyun_http'
local mqtt_app = require 'app.base.mqtt'


local sub_topics = {
	"app/#",
	"sys/#",
	"output/#",
	"command/#",
}

--- 注册对象(请尽量使用唯一的标识字符串)
local app = mqtt_app:subclass("ALIYUN_MQTT_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	mqtt_app.initialize(self, name, sys, conf)

	self._client_id = conf.mqtt_id or sys:id() -- using system device id
	self._product_key = conf.product_key or "5NjhcjHuFPS"
	self._device_name = conf.device_name or "demo1"
	self._device_secret = conf.device_secret or "QnINbT0Oze4YHCe83lsVvM6RQH66BnLA"
	self._server_host = conf.server or "iot-as-mqtt.cn-shanghai.aliyuncs.com"
	self._server_port = conf.port or "1883"
	self._enable_https = conf.enable_https or false
	self._enable_tls = conf.enable_tls or false
	self._http_server = conf.http_server or "iot-auth.cn-shanghai.aliyuncs.com"
	self._http_api = aliyun_http:new(sys, self._http_server, self._product_key)

	self._mqtt_topic = string.format("/%s/%s", self._product_key, self._device_name)
	--self._mqtt_topic = ""
end

--- 
-- 返回MQTT认证信息，包含连接信息
-- client_id, username, password, clean_session, host , port, enable_tls, tls_cert
--
function app:mqtt_auth()
	local mqtt_id = self._mqtt_id
	local host = self._product_key .. "." .. self._server_host
	local port = self._server_port
	local enable_tls = self._enable_tls

	if not self._enable_https then
		local securemode = enable_tls and 2 or 3
		local timestamp = math.floor((self._sys:time() % 1) * 1000)
		local client_id = mqtt_id.."|securemode="..securemode..",signmethod=hmacsha1,timestamp="..timestamp.."|"
		local username = self._device_name.."&"..self._product_key
		local password = self._http_api:gen_sign(self._device_name, self._device_secret, mqtt_id, timestamp)

		self._log:debug("Aliyun MQTT Client", client_id, username, password)

		return {
			client_id = client_id,
			username = username,
			password = password,
			clean_session = true,
			host = host,
			port = port,
			enable_tls = enable_tls,
			tls_cert = "root_cert.crt",
		}
	else
		local r, err = self._http_api:auth(self._device_name, self._device_secret, mqtt_id)
		if not r then
			self._log:error("Auth failed", err)
			return nil, err
		end

		self._refresh_token_timeout = os.time() + (24 * 3600)

		username = r.iotId
		password = r.iotToken
		enable_tls = true

		self._log:debug("Aliyun MQTT Client", mqtt_id, username, password)

		if r.resources and r.resources.mqtt then
			host = r.resources.mqtt.host
			port = r.resources.mqtt.port
		end

		return {
			client_id = client_id,
			username = username,
			password = password,
			clean_session = true,
			host = host,
			port = port,
			enable_tls = enable_tls,
			tls_cert = "root_cert.crt",
		}
	end
end

function app:on_publish_data(key, value, timestamp, quality)
	local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	local msg = {
		sn = sn,
		input = input,
		prop = prop,
		value = value,
		timestamp = timestamp,
		quality = quality
	}
	return self:publish(self._mqtt_topic.."/data", cjson.encode(msg), 1, false)
end

function app:on_publish_data_list(val_list)
	for _, v in ipairs(val_list) do
		self:on_publish_data(table.unpack(v))
	end
end


function app:on_event(app, sn, level, data, timestamp)
	local msg = {
		app = app,
		sn = sn,
		level = level,
		data = data,
		timestamp = timestamp,
	}
	return self:publish(self._mqtt_topic.."/events", cjson.encode(msg), 1, false)
end

function app:on_stat(app, sn, stat, prop, value, timestamp)
	local msg = {
		app = app,
		sn = sn,
		stat = stat,
		prop = prop,
		value = value,
		timestamp = timestamp,
	}
	return self:publish(self._mqtt_topic.."/statistics", cjson.encode(msg), 1, false)
end

function app:on_publish_devices(devices)
	return self:publish(self._mqtt_topic.."/devices", cjson.encode(devices), 1, true)
end

function app:on_mqtt_connect_ok()
	for _, v in ipairs(sub_topics) do
		self:subscribe("/"..v, 1)
	end
	return self:publish(self._mqtt_topic.."/status", cjson.encode({device=mqtt_id, status="ONLINE"}), 1, true)
end

function app:on_mqtt_message(...)
	print(...)
end

function app:mqtt_will()
	return self._mqtt_topic.."/status", cjson.encode({device=mqtt_id, status="OFFLINE"}), 1, true
end

--- 返回应用对象
return app

