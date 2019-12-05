local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'
local ioe = require 'ioe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = mqtt_app:subclass("MQTT_EXAMPLE_APP_IN_GUIDE")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.static.API_VER = 5

function app:on_init()
	local conf = self._conf
	conf.server = "192.168.1.100"
	conf.port = 1883

	self._mqtt_id = self._sys:id()
end

function app:on_publish_devices(devices)
	local new_devices = {}
	for k, v in pairs(self._enable_devices) do
		if v then
			new_devices[k] = devices[k]
		end
	end

	local data, err = cjson.encode(new_devices)
	if not data then
		self._log:error("Devices data json encode failed", err)
		return false
	end

	return self:publish(self._mqtt_id.."/devices", data, 1, true)
end

function app:on_publish_data(key, value, timestamp, quality)
	--local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	local msg = {{ key, value, timestamp, quality}}
	return self:publish(self._mqtt_id.."/data", cjson.encode(msg), 0, false)
end

function app:on_publish_data_em(key, value, timestamp, quality)
	return self:on_publish_data(key, value, timestamp, quality)
end

function app:on_publish_data_list(val_list)
    local data=cjson.encode(val_list)
	return self:publish(self._mqtt_id.."/data", data, 0, false)
end

function app:on_event(app, sn, level, type_, info, data, timestamp)
	local event = {
		level = level,
		['type'] = type_,
		info = info,
		data = data,
		app = app
	}
	return self:publish(self._mqtt_id.."/event", cjson.encode({sn, event, timestamp} ), 1, false)
end

function app:on_mqtt_connect_ok()
	--- subscribe output/command
	self:subscribe(self._mqtt_id..'/output/#', 1)
	self:subscribe(self._mqtt_id..'/command/#', 1)
	--- send online status
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
