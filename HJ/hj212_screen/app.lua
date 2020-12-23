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
	conf.port = conf.port or '1883'
	conf.period = 0 -- disable Period Buffer

	-- for test
	conf.app_inst = 'test'
	conf.port = 3883
	conf.settings = conf.settings or {
		{name='Kv', value='10.2'}
	}

	--- 基础类初始化
	mqtt_app.initialize(self, name, sys, conf)

	self._mqtt_id = conf.client_id

	self._prop_buf = {
		RDATA = {},
		MIN = {},
		HOUR = {},
		DAY = {},
	}
end

function app:on_start()
	local conf = self:app_conf()
	local sys = self:sys_api()
	local log = self:log_api()
	local sys_id = sys:id()

	local tpl_file = string.format('%s/tpl/%s.csv', sys:app_dir(), conf.station_type or 'example')
	local tpl, err = tpl_parser(tpl_file)
	if not tpl then
		return nil, err
	end
	self._tpl = tpl

	local devs = {}
	local inputs = {}
	local tags = {}
	for _, v in ipairs(tpl.props) do
		if not v.setting then
			local dev_sn = sys_id..'.'..(conf.station or 'HJ212')
			if v.sn then
				dev_sn = dev_sn .. '.' ..v.sn
			end
			devs[dev_sn] = devs[dev_sn] or {}
			devs[dev_sn][v.input] = v
			tags[v.name] = {
				value = 0,
				timestamp = sys:time(),
				station = v.sn == nil
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
	self._tags = tags
	local settings = {}
	for _, v in ipairs(conf.settings) do
		settings[v.name] = v.value
	end
	self._settings = settings
	for _, v in ipairs(inputs) do
		if not settings[v.name] then
			return nil, "Mising settings value"
		end
		log:info("Setting:", v.name, settings[v.name])
	end

	local meta = self._api:default_meta()
	meta.name = 'HJ212 Settings' 
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'HJ212 Smart Device Settings' 
	meta.series = 'N/A'

	local dev_sn = sys_id..'.HJ212.SETTINGS'
	self._dev_sn = dev_sn
	self._dev = self._api:add_device(dev_sn, meta, inputs)

	sys:timeout(10, function()
		for _, v in ipairs(inputs) do
			self._dev:set_input_prop(v.name, 'value', self._settings[v.name])
		end
		local api = self:data_api()
		local tags = self._tags
		for sn, dev in pairs(self._devs) do
			local dev_api = api:get_device(sn)
			if dev_api then
				for input, v in pairs(dev) do
					local value, timestamp = dev_api:get_input_prop(v.input, 'value')
					print('GOT', v.input, value, timestamp)
					if value then
						tags[v.name].value = value
						tags[v.name].timestamp = timestamp
					end
				end
			end
		end
	end)

	self._ctrl_no = 1
	self._ctrl_co = {}
	self._ctrl_results = {}
	self._app_reg = nil

	return mqtt_app.on_start(self)
end

function app:hj212_ctrl(cmd, param, timeout)
	assert(cmd)
	local param = param or {}
	local timeout = timeout or 3000

	local api = self:data_api()
	local sys = self:sys_api()
	local conf = self:app_conf()

	local t = {id = self._ctrl_no, cmd = cmd}
	self._ctrl_no = self._ctrl_no + 1

	self._ctrl_co[t.id] = t
	api:send_ctrl(conf.app_inst, 'unreg', param, t)

	sys:sleep(timeout, t)
	self._ctrl_co[t.id] = nil

	if self._ctrl_results[t.id] then
		return table.unpack(self._ctrl_results[t.id])
	end

	return nil, "Timeout"
end

function app:on_ctrl_result(app_src, priv, result, err)
	local sys = self:sys_api()
	if priv and self._ctrl_co[priv.id] then
		self._ctrl_results[priv.id] = {result, err}
		sys:wakeup(self._ctrl_co[priv.id])
	else
		self._log:error("Timeout result", priv.id, priv.cmd)
	end
end

function app:on_run(tms)
	local sys = self:sys_api()

	local now = sys:now()
	if not self._app_reg then
		self._app_reg = now
		local r, err = self:hj212_ctrl('reg')
		if not r then
			self._app_reg = sys:now()
			self._log:error("Failed to reg to HJ212 application", err)
		end
	else
		if now - self._app_reg > 10000 then
			self._app_reg = now
			local r, err = self:hj212_ctrl('ping')
			if not r then
				self._app_reg = nil
			end
		end
	end

	local data = {}
	data.TS = sys:time()
	data.id = 1
	for k, v in pairs(self._tags) do
		data[k] = v.value
	end

	self:publish('/data', cjson.encode(data), 1, false)

	return 1000
end

function app:on_close()
	if self._app_reg then
		self:hj212_ctrl('unreg')
		self._app_reg = false
	end

	mqtt_app.on_close(self)
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
	if quality ~= 0 then
		return true
	end

	local tpl_prop = self._devs[sn][input]
	if not tpl_prop then
		return true
	end

	if prop ~= 'value' then
		value = assert(cjson.decode(value))
	end
	local tag = self._tags[tpl_prop.name]
	assert(tag)

	if prop == 'value' then
		tag.value = value
		tag.timestamp = timestamp
	else
		if tag.station then
			self:publish_prop_data(tpl_prop.name, prop, value, timestamp)
		end
	end

	return true
end

function app:publish_prop_data(tag_name, prop, value, timestamp)
	local timestamp = math.floor(timestamp)
	local sys = self:sys_api()
	local log = self:log_api()
	local prop = prop
	assert(self._prop_buf[prop])
	local buf = self._prop_buf[prop][timestamp]
	if not buf then
		local name = prop..'['..os.date('%c', timestamp)..']'
		log:debug("Create publish prop data item", name)
		buf = {
			id = {},
			list = {},
			completed = false
		}
		self._prop_buf[prop][timestamp] = buf

		sys:fork(function()
			sys:sleep(3000, buf.id)
			if not buf.completed then
				log:error("Uncompleted item", name)
				for k, v in pairs(self._tags) do
					if v.station and not buf.list[k] then
						log:error('Missing item', k)
					end
				end
			else
				log:debug("Completed item", name)
				local list = buf.list
				self._prop_buf[prop][timestamp] = nil
				buf = nil

				self:publish_prop_list(prop, list, timestamp)
			end
		end)
	end

	log:debug(tag_name, prop, value, timestamp)
	buf.list[tag_name] = value

	for k, v in pairs(self._tags) do
		if v.station and not buf.list[k] then
			return
		end
	end
	buf.completed = true
	log:debug("Completed item", prop)
	sys:wakeup(buf.id)
end

function app:publish_prop_list(prop, list, timestamp)
	local data = {
		TS = timestamp,
		id = os.time()
	}
	for k, v in pairs(list) do
		data[string.upper(prop)..k] = v
	end
	return self:publish('/prop_data', cjson.encode(data), 1, false)
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

--- 返回应用对象
return app
