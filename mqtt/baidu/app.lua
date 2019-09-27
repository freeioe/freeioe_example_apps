local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'

local sub_topics = {
	"app/#",
	"sys/#",
	"output/#",
	"command/#",
}

--- 注册对象(请尽量使用唯一的标识字符串)
local app = mqtt_app:subclass("BAIDU_YUN_MQTT_APP")
--- 设定应用最小运行接口版本(目前版本为5,为了以后的接口兼容性)
app.static.API_VER = 5

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	--- 更新默认配置
	conf.username = conf.username or "symlinkdemo/demo"
	conf.password = conf.password or "qWZ/lxXqz2W33NZir6MW13RpCPAFELSiirVvGDfaaQw="
	conf.server = conf.server or "symlinkdemo.mqtt.iot.bj.baidubce.com"
	conf.port = conf.port or 1883
	conf.enable_tls = conf.enable_tls or false
	conf.tls_cert = "root_cert.pem"

	--- 基础类初始化
	mqtt_app.initialize(self, name, sys, conf)

	self._mqtt_topic_prefix = ''
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
	return self:publish(self._mqtt_topic_prefix.."/data", cjson.encode(msg), 1, false)
end

function app:on_publish_data_list(val_list)
	for _, v in ipairs(val_list) do
		self:on_publish_data(table.unpack(v))
	end
	return true
end


function app:on_event(app, sn, level, type_, info, data, timestamp)
	local msg = {
		app = app,
		sn = sn,
		['type'] = type_,
		level = level,
		info = info,
		data = data,
		timestamp = timestamp,
	}
	return self:publish(self._mqtt_topic_prefix.."/events", cjson.encode(msg), 1, false)
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
	return self:publish(self._mqtt_topic_prefix.."/statistics", cjson.encode(msg), 1, false)
end

function app:on_publish_devices(devices)
	return self:publish(self._mqtt_topic_prefix.."/devices", cjson.encode(devices), 1, true)
end

function app:on_mqtt_connect_ok()
	for _, v in ipairs(sub_topics) do
		self:subscribe("/"..v, 1)
	end
	return self:publish(self._mqtt_topic_prefix.."/status", cjson.encode({device=mqtt_id, status="ONLINE"}), 1, true)
end

function app:on_mqtt_message(mid, data, qos, retained)
	--print(...)
end

function app:mqtt_will()
	return self._mqtt_topic_prefix.."/status", cjson.encode({device=mqtt_id, status="OFFLINE"}), 1, true
end

--- 返回应用对象
return app


