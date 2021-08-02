local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'
local http_auth = require 'http_auth'
local uuid = require 'uuid'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = mqtt_app:subclass("BAIDU_YUN_MQTT_APP")
--- 设定应用最小运行接口版本(目前版本为5,为了以后的接口兼容性)
app.static.API_VER = 5

function app:on_init(name, sys, conf)
	self._mqtt_topic_prefix = 'things/'..conf.product_key..'/'..conf.device_name
	self._http_auth = http_auth:new(sys, conf.instance, conf.addr, conf.product_key, conf.device_name, conf.device_secret)
end

function app:mqtt_auth()
	local r, err = self._http_auth:auth()
	if not r and r.content then
		local content = r.content
		local mqtt_id = content.clientId
		local mqtt_host = content.broker
		local mqtt_port = 1883
		local username = content.username
		local password = content.password

		return {
			client_id = mqtt_id,
			username = username,
			password = password,
			clean_session = true,
			host = mqtt_host,
			port = mqtt_port,
		}
	else
		return nil, err or "Cannot auth with http server"
	end
end

function app:on_publish_data(key, value, timestamp, quality)
	local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	local msg = {
		reqId = uuid.new(),
		method = "thing.property.post",
		version = "1.0",
		timestamp = (timestamp * 1000) // 1,
		properties = {
			[input] = value
		}
	}
	return self:publish(self._mqtt_topic_prefix.."/property/post", cjson.encode(msg), 1, false)
end

function app:on_publish_data_list(val_list)
	for _, v in ipairs(val_list) do
		self:on_publish_data(table.unpack(v))
	end
	return true
end


--[[
function app:on_event(app, sn, level, type_, info, data, timestamp)
	return self:publish(self._mqtt_topic_prefix.."/events", cjson.encode(msg), 1, false)

end
]]--

function app:on_publish_cached_data_list(val_list)
	local data = {} -- TODO: convert val_list to data
	data = {
		{
			timestamp = os.time() * 1000,
			events = {
				sensors = {
					tag1 = 12,
					tag2 = 23,
				},
				coordinate = {
					longitude = 0,
					latitude = 0,
				}
			}
		},
		{
			timestamp = os.time() * 1000,
			events = {
				sensors = {
					tag1 = 12,
					tag2 = 23,
				},
				coordinate = {
					longitude = 0,
					latitude = 0,
				}
			}
		},
	}
	local msg = {
		reqId = uuid.new(),
		method = "thing.event.batch",
		version = "1.0",
		timestamp = (timestamp * 1000) // 1,
		data = data
	}
	return self:publish(self._mqtt_topic_prefix.."/event/batch", cjson.encode(msg), 1, false)
end

function app:on_publish_devices(devices)
	return true
	--return self:publish(self._mqtt_topic_prefix.."/devices", cjson.encode(devices), 1, true)
end

function app:on_mqtt_connect_ok()
	local c = self:app_conf()
	self:subscribe('thing.'..c.product_key..'/'..c.device_name..'/property/invoke', 1) -- 可写属性更新
	self:subscribe('thing.'..c.product_key..'/'..c.device_name..'/command/invoke', 1) -- 可写属性更新
	self:subscribe('thing.'..c.product_key..'/'..c.device_name..'/response/c2d', 1) -- 云端调用响应

	return self:publish(self._mqtt_topic_prefix.."/status", cjson.encode({device=mqtt_id, status="ONLINE"}), 1, true)
end

function app:on_mqtt_message(mid, data, qos, retained)
	--print(...)
	-- invodke 
	local property_example = [[
{
	"reqId":<uuid>,
	"method":"thing.property.invoke",
	"version":"1.0",
	"timestamp":1610212132010, --ms
	"properties":{
		"log_url":"http://xxx.xxx.xx.xx"
	}
}
]]
	local command_example = [[
{
	"reqId":<uuid>,
	"method":"thing.command.invoke",
	"version":"1.0",
	"timestamp":1610212132010, --ms
	"params":{
		"test":"hello world",
		"format":"plain text"
	}
}
]]

	local response_example = [[
{
	"reqId":<uuid>,
	"method":"thing.property.post",
	"code":200,
	"description":"The property 'sn' has been updated successfully."
}
]]
end

function app:c2d_result(method, code, desc, params)
	local msg = {
		reqId = uuid.new(),
		method = method,  -- e.g. "thing.property.invoke
		code = code,
		description = desc,
		params = params
	}
	return self:publish(self._mqtt_topic_prefix.."/reponse/d2c", cjson.encode(msg), 1, false)
end

function app:mqtt_will()
	return self._mqtt_topic_prefix.."/status", cjson.encode({device=mqtt_id, status="OFFLINE"}), 1, true
end

--- 返回应用对象
return app


