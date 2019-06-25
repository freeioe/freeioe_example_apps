local huawei_http = require 'huawei_http'
local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'

local categories = {
	"event",
	"data",
	"rawData",
	"alarm",
	"command",
	"reply",
	"response",
}

local function huawei_timestamp(timestamp)
	return os.date("%Y%m%dT%H%M%SZ", math.floor(timestamp))
end

--- 注册对象(请尽量使用唯一的标识字符串)
local app = mqtt_app:subclass("HUAWEI_IOT_CLOUD")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.static.API_VER = 4

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	mqtt_app.initialize(self, name, sys, conf)

	self._device_id = conf.device_id or "6bcfe38c-936b-4ffb-9913-54ef2232ba9a"
	self._secret = conf.secret or "2efe9e3c6d7ca4317c18"

	--- HTTP Configruation
	local host = conf.server or "117.78.47.188"
	local port = conf.port or "8943"
	local app_id = conf.app_id or "fxfB_JFz_rvuihHjxOj_kpWcgjQb"

	self._huawei_http = huawei_http:new(self._sys, host, port, app_id)
end

--- Auth mqtt
function app:mqtt_auth()
	local r, err = self._huawei_http:login(self._device_id, self._secret)
	if r then
		if r and r.refreshToken then
			self._retry_login = 100

			self._log:notice("HuaWei login done!", cjson.encode(r))
			self._huawei_http:set_access_token(r.accessToken)

			local mqtt_id = r.mqttClientId
			local mqtt_host = r.addrHAServer
			local mqtt_port = 8883
			local username = self._device_id
			local password = self._secret

			self._refresh_token = r.refreshToken
			self._refresh_token_timeout = os.time() + (r.timeout or 43199)

			return {
				client_id = mqtt_id,
				username = username,
				password = password,
				clean_session = true,
				host = mqtt_host,
				port = mqtt_port,
				enable_tls = true,
				tls_cert = "rootcert.pem",
			}
		else
			return nil, "cannot find the token"
		end
	end

	return nil, err
end

function app:create_event_msg(app, sn, level, data, timestamp)
	return {
		header = {
			eventType = "event",
			from = "/devices/"..self._device_id.."/services/"..sn,
			to = "/event/v1.1.0/devices/"..self._device_id.."/services/"..sn,
			access_token = self._refresh_token,
			timestamp = huawei_timestamp(timestamp),
			eventTime = huawei_timestamp(timestamp),
		},
		body = {
			app = app,
			sn = sn,
			level = level,
			data = data,
			timestamp = timestamp
		},
	}
end

function app:create_data_msg(sn, input, prop, value, timestamp, quality)
	return {
		header = {
			method = "PUT",
			from = "/device/"..sn,
			to = "/data/v1.1.0/devices/"..sn.."/services/data",
			access_token = self._refresh_token,
			timestamp = huawei_timestamp(timestamp),
			eventTime = huawei_timestamp(timestamp),
		},
		body = {
			sn = sn,
			input = input,
			prop = prop,
			value = value,
			timestamp = timestamp,
			quality = quality
		}
	}
end

function app:on_publish_data(key, value, timestamp, quality)
	local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	assert(sn and input and prop)
	local msg = self:create_data_msg(sn, input, prop, value, timestamp, quality)
	return self:publish(".cloud.signaltrans.v2.categories.data", cjson.encode(msg), 1, false)
end

function app:on_publish_data_list(val_list)
	for _, v in ipairs(val_list) do
		self:on_publish_data(table.unpack(v))
	end
	return true
end

function app:on_event(app, sn, level, data, timestamp)
	local msg = self:create_event_msg("event", app, sn, level, data, timestamp)
	return self:publish(".cloud.signaltrans.v2.categories.event", cjson.encode(msg), 1, false)
end

function app:on_stat(app, sn, stat, prop, value, timestamp)
end

function app:on_publish_devices(devices)
	local r, err = self._huawei_http:sync_devices(devs)
	if not r then
		self._log:error("Sync device failed", err)
		return nil, err
	end
	self._log:debug("Sync device return", cjson.encode(r))
	return true
end

function app:huawei_http_refresh_token()
	local r, err = self._huawei_http:refresh_token(self._refresh_token)
	if r then
		if r and r.refreshToken then
			self._log:notice("Refresh token done!", cjson.encode(r))
			self._huawei_http:set_access_token(r.accessToken)
			self._refresh_token = r.refreshToken
			self._refresh_token_timeout = os.time() + (r.timeout or 43199)
			return true
		end
	end
	-- TODO: disconnect mqtt
	return nil, err
end

--- 应用运行入口
function app:on_run(tms)
	if self._refresh_token_timeout and self._refresh_token_timeout - os.time() < 60  then
		self:huawei_http_refresh_token()
	end

	return 1000  -- one second
end

--- 返回应用对象
return app

