local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'
local ioe = require 'ioe'
local tpl_parser = require 'tpl_parser'

local app = mqtt_app:subclass("HJ212_APP_SCREEN")
app.static.API_VER = 8

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
	local sys_id = sys:id()

	-- MQTT
	conf.client_id = conf.client_id or sys_id
	conf.server = conf.server or '127.0.0.1'
	conf.port = conf.port or '3883'
	conf.period = 0 -- disable Period Buffer

	local mqtt_conf = self:to_mqtt_app_conf(conf, sys_id)

	--- 基础类初始化
	mqtt_app.initialize(self, name, sys, mqtt_conf)

	self._mqtt_id = mqtt_conf.client_id
end

function app:on_start()
	local conf = self:app_conf()
	local sys = self:sys_api()
	local log = self:log_api()
	local sys_id = sys:id()

	local tpl_file = string.format('%s/tpl/%s.csv', sys:app_dir(), conf.station or 'example')
	local tpl, err = tpl_parser(tpl_file)
	if not tpl then
		return nil, err
	end
	self._tpl = tpl

	local devs = {}
	local inputs = {}
	for _, v in ipairs(tpl.props) do
		if not v.setting then
			local dev_sn = sys_id..'.HJ212_'..conf.app_inst
			if v.sn then
				dev_sn = dev_sn .. '.' ..v.sn
			end
			devs[dev_sn] = devs[dev_sn] or {}
			devs[dev_sn][v.input] = {
				prop = v,
				value = nil,
				timestamp = nil
			}
		else
			inputs[#inputs + 1] = {
				name = v.name,
				desc = v.desc,
				vt = v.input == 'int' and 'int' or 'float'
			}
		end
	end
	self._devs = devs

	local meta = self._api:default_meta()
	meta.name = 'HJ212 Settings' 
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'HJ212 Smart Device Settings' 
	meta.series = 'N/A'

	local dev_sn = sys_id..'.HJ212_SETTINGS'
	self._dev_sn = dev_sn
	self._dev = self._api:add_device(dev_sn, meta, inputs)


	return mqtt_app.on_start(self)
end

function app:pack_key(app_src, device_sn, ...)
	--- if deivce not in allowed list
	if not self._devs[device_sn] then
		return
	end
	if dev_sn == self._dev_sn then
		return
	end

	--- using the base pack key
	return mqtt_app.pack_key(self, app_src, device_sn, ...)
end

function app:on_publish_data(key, value, timestamp, quality)
	local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	if prop ~= 'value' or quality ~= 0 then
		return true
	end

	local tag = self._devs[sn][input]
	if not tag then
		return true
	end

	tag.value = value
	tag.timestamp = timestamp

	return true
end

function app:on_publish_data_list(val_list)
	assert(false, "Should not be here")
end

function app:on_publish_cached_data_list(val_list)
	assert(false, "Should not be here")
end

function app:on_event(app, sn, level, type_, info, data, timestamp)
	if not self._devs[sn] then
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

function app:on_publish_devices(devices)
	if self._disable_devices then
		return true
	end
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
	if not self._enable_devices[data.device] then
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
	if not self._enable_devices[data.device] then
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

function app:on_ctrl_result(app_src, priv, result, err)
	print('on_ctrl_result', app_src, priv, result, err)
end

--- 返回应用对象
return app
