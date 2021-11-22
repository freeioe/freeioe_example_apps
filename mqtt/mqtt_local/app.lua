local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'
local sha1 = require 'hashings.sha1'
local hmac = require 'hashings.hmac'
local ioe = require 'ioe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = mqtt_app:subclass("MQTT_LOCAL_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.static.API_VER = 8

function app:to_mqtt_app_conf(conf)
	conf.mqtt = conf.mqtt or {}
	local new_conf = {
		--- mqtt
		client_id = conf.mqtt.client_id and conf.mqtt.client_id ~= '' and conf.mqtt.client_id or nil,
		username = conf.mqtt.username and conf.mqtt.username ~= '' and conf.mqtt.username or 'mqtt',
		password = conf.mqtt.password and conf.mqtt.password ~= '' and conf.mqtt.password or 'passwd',
		server = conf.mqtt.server or '127.0.0.1',
		port = conf.mqtt.port or 1883,
	}

	--- Test
	-- new_conf.port = 3883

	self._upload_period = conf.options.period or 5
	if self._upload_period < 1 then
		self._upload_period = 5
	end
	return new_conf
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
	self._enabled_devices = {}

	for _, v in ipairs(conf.devs or {}) do
		if not valid_device_sn(v.sn) then
			log:error("Device SN is not valid", v.sn)
		end

		if v.sn and string.len(v.sn) > 0 then
			self._enabled_devices[v.sn] = true
		else
			log:warning("Device missing sn in conf.devs item")
		end
	end

	local sys_id = sys:id()

	local mqtt_conf = self:to_mqtt_app_conf(conf)
	if not mqtt_conf.client_id then
		mqtt_conf.client_id = sys_id
	end

	--- 基础类初始化
	mqtt_app.initialize(self, name, sys, mqtt_conf)

	self._mqtt_id = mqtt_conf.client_id
end

function app:pack_key(app_src, device_sn, ...)
	--- We using data snapshot so skip all data change
	return
end

function app:on_publish_data(key, value, timestamp, quality)
	return true
end

function app:on_publish_data_list(val_list)
	return true
end

function app:on_event(app, sn, level, type_, info, data, timestamp)
	if not self._enabled_devices[sn] then
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

function app:on_run(tms)
	self:upload_device_snapshot()	
	return self._upload_period * 1000
end

function app:upload_device_snapshot()
	local api = self:data_api()
	local value_map = {}

	for sn, dev in pairs(self._enabled_devices) do
		local val_list = {}
		local dev_api = api:get_device(sn)
		if dev_api then
			dev_api:list_inputs(function(input, prop, value, timestamp, quality)
				if prop == 'value' then
					table.insert(val_list, {
						input = input,
						value = value,
						timestamp = timestamp,
						quality = quality
					})
				end
			end)
		else
			self._log:error("Failed to find device", sn)
		end
		value_map[sn] = val_list
	end
	local str, err = cjson.encode(value_map)
	if not str then
		self._log:error("JSON encode error", err)
		return nil, err
	end
	return self:publish(self._mqtt_id.."/data", str, 1, true)
end

function app:on_publish_devices(devices)
	local new_devices = {}
	for k, v in pairs(self._enabled_devices) do
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
	if not self._enabled_devices[data.device] then
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
	if not self._enabled_devices[data.device] then
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
