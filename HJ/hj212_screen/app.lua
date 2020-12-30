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
	conf.disable_cov = true -- disable COV

	-- defaults
	conf.station = conf.station or 'HJ212'
	conf.station_type = conf.station_type or 'VOCs'

	-- for test
	--[[
	conf.port = 3883
	conf.settings = {
		{name='section_area', value='11.2'},
		{name='filed_coefficient', value='1'},
		{name='local_Pressure', value='10.2'},
	}
	]]--

	--- 基础类初始化
	mqtt_app.initialize(self, name, sys, conf)

	self._mqtt_id = conf.station
	self._devs = {}

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

	self._log:info("Wait for station application instance", conf.station)
	conf.app_inst = ioe.env.wait('HJ212.STATION', conf.station)
	self._log:info("Got application instance name", conf.app_inst)

	local tpl_file = string.format('%s/tpl/%s.csv', sys:app_dir(), conf.station_type)
	local tpl, err = tpl_parser(tpl_file, function(...)
		log:error(...)
	end)
	if not tpl then
		return nil, err
	end
	self._tpl = tpl

	local inputs = {
		{ name = 'station', desc = 'Station name', vt = 'string'},
		{ name = 'station_type', desc = 'Station type', vt = 'string'},
		{ name = 'app_inst', desc = 'Station app instance name', vt = 'string'},
	}
	local value_map = {
		station = { value = conf.station },
		station_type = { value = conf.station_type },
		app_inst = { value = conf.app_inst }
	}
	local outputs = {}
	local inputs_map = {}
	local status_map = {}
	local settings_map = {}
	local devs = {}

	local station_sn = sys_id..'.'..conf.station
	local function map_dev_sn(sn)
		local sn = sn or 'STATION'
		sn = string.gsub(sn, '^STATION(.*)$', station_sn..'%1')
		sn = string.gsub(sn, '^GW(.*)$', sys_id..'%1')
		return sn
	end
	local function map_dev(prop)
		prop.sn = map_dev_sn(prop.sn)
		devs[prop.sn] = devs[prop.sn] or {}
		devs[prop.sn][prop.input] = devs[prop.sn][prop.input] or {}
		table.insert(devs[prop.sn][prop.input], prop)
	end

	for _, v in ipairs(tpl.inputs) do
		map_dev(v)
		inputs_map[v.name] = v
		inputs[#inputs + 1] = {
			name = v.name,
			desc = string.format('[%s]%s', v.input, v.desc),
		}
	end
	for _, v in ipairs(tpl.status) do
		map_dev(v)
		status_map[v.name] = v
		inputs[#inputs + 1] = {
			name = v.name,
			desc = v.desc,
		}
	end
	for _, v in ipairs(tpl.settings) do
		settings_map[v.name] = v
		inputs[#inputs + 1] = {
			name = v.name,
			desc = v.desc,
			vt = v.vt
		}
		table.insert(outputs, inputs[#inputs])
		inputs[#inputs + 1] = {
			name = v.hj212,
			desc = v.desc,
			vt = v.vt
		}
	end

	for _, v in ipairs(conf.settings) do
		log:info("Setting:", v.name, v.value)
		value_map[v.name] = { value = v.value }
		local setting = settings_map[v.name]
		value_map[setting.hj212] = { value = v.value }
	end
	for k, v in pairs(settings_map) do
		if not value_map[k] then
			return nil, string.format("Mising settings [%s] value", k)
		end
	end

	self._devs = devs
	self._inputs = inputs
	self._outputs = outputs
	self._inputs_map = inputs_map
	self._status_map = status_map
	self._settings_map = settings_map
	self._value_map = value_map

	local meta = self._api:default_meta()
	meta.name = 'HJ212 Settings' 
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'HJ212 Smart Device Settings' 
	meta.series = 'N/A'

	local dev_sn = sys_id..'.'..conf.station..'.SETTINGS'
	self._dev_sn = dev_sn
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs)
	self._dev_inputs = inputs

	sys:timeout(10, function()
		self:read_tags()
	end)

	self._ctrl_no = 1
	self._ctrl_co = {}
	self._ctrl_results = {}
	self._app_reg = nil

	return mqtt_app.on_start(self)
end

function app:read_tags()
	local api = self:data_api()
	local value_map = self._value_map
	for sn, dev in pairs(self._devs) do
		local dev_api = api:get_device(sn)
		if dev_api then
			for input, props in pairs(dev) do
				local value, timestamp = dev_api:get_input_prop(input, 'value')
				if value ~= nil then
					self._log:debug("Input value got", sn, input, value, timestamp)
				else
					--self._log:error("Failed to read input value", sn, input)
					value = 0
				end
				for _, prop in ipairs(props) do
					value_map[prop.name] = { value = value, timestamp = timestamp }
				end
			end
		else
			self._log:error("Failed to find device", sn)
		end
	end

	for k, v in pairs(value_map) do
		v.timestamp = v.timestamp or ioe.time()
		self._dev:set_input_prop(k, 'value', v.value, v.timestamp)
	end
end

function app:hj212_ctrl(cmd, param, timeout)
	if cmd then
		return true
	end
	assert(cmd)
	local param = param or {}
	local timeout = timeout or 3000

	local api = self:data_api()
	local sys = self:sys_api()
	local conf = self:app_conf()

	local t = {id = self._ctrl_no, cmd = cmd}
	self._ctrl_no = self._ctrl_no + 1

	self._ctrl_co[t.id] = t
	api:send_ctrl(conf.app_inst, cmd, param, t)

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
	local value_map = self._value_map
	if self._dev then
		for k, v in pairs(value_map) do
			if not v.timestamp or v.timestamp < ioe.time() - 5 then
				v.timestamp = ioe.time()
				self._dev:set_input_prop(k, 'value', v.value or 0)
			end
		end
	end

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

	self:publish_status()
	self:publish_inputs()

	return 1000
end

function app:publish_status()
	local data = {}
	local value_map = self._value_map
	for k, v in pairs(self._status_map) do
		if value_map[k] then
			data['Gsys_'..k] = self._value_map[k].value
		else
			self._log:error('Status value not found', k)
		end
	end
	local now = math.floor(ioe.time())
	data.Gsys_timeStr = os.date('%F %T', now)
	data.Gsys_UTC = now
	local d = os.date("*t", now)
	data.Gsys_year = d.year
	data.Gsys_month = d.month
	data.Gsys_day = d.day
	data.Gsys_hour = d.hour
	data.Gsys_minute = d.min
	data.Gsys_second = d.sec
	data.Gsys_year = d.year

	return self:publish('inputs/gsys', cjson.encode({
		datas = data,
		time_utc = now,
		time_str = os.date("%F %T", now)
	}), 1, true)
end

function app:publish_inputs()
	local data = {}
	local value_map = self._value_map
	for k, v in pairs(self._inputs_map) do
		if value_map[k] then
			data['GIO_'..k] = self._value_map[k].value
		else
			self._log:error('Input value not found', k)
		end
	end
	local now = math.floor(ioe.time())
	data.Grt_Time = os.date('%F %T', now)
	data.Grt_ID = now

	return self:publish('inputs/gio', cjson.encode({
		datas = data,
		time_utc = now,
		time_str = os.date("%F %T", now)
	}), 1, true)
end

function app:on_close()
	if self._app_reg then
		self:hj212_ctrl('unreg')
		self._app_reg = false
	end

	return mqtt_app.on_close(self)
end

function app:pack_key(app_src, device_sn, input, ...)
	if dev_sn == self._dev_sn then
		return
	end
	--- if deivce not in allowed list
	if not self._devs[device_sn] then
		return
	end
	if not self._devs[device_sn][input] then
		return
	end
	--- using the base pack key
	return mqtt_app.pack_key(self, app_src, device_sn, input, ...)
end

function app:on_publish_data(key, value, timestamp, quality)
	local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	if quality ~= 0 then
		return true
	end

	local tpl_props = self._devs[sn][input]
	if not tpl_props then
		return true
	end

	if prop ~= 'value' then
		value = assert(cjson.decode(value))
	end

	for _, tpl_prop in ipairs(tpl_props) do
		local tag = self._inputs_map[tpl_prop.name] or self._status_map[tpl_prop.name]
		assert(tag, string.format("missing input map:%s", tpl_prop.name))

		if prop ~= 'value' then
			self:publish_prop_data(tpl_prop.name, prop, value, timestamp)
		else
			self._value_map[tag.name] = {value = value, timestamp = timestamp}
		end
	end

	return true
end

function app:publish_prop_data(tag_name, prop, value, timestamp)
	local timestamp = math.floor(timestamp)
	local sys = self:sys_api()
	local log = self:log_api()
	local prop = prop
	assert(self._prop_buf[prop], string.format('Prop %s invalid!', prop))
	local buf = self._prop_buf[prop][timestamp]
	if not buf then
		local name = prop..'['..os.date('%c', timestamp)..']'
		--log:debug("Create publish prop data item", name)
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
				for k, v in pairs(self._inputs_map) do
					if not buf.list[k] then
						log:error('Missing item', k, name)
					else
						log:debug('Has item', k, name)
					end
				end
			end

			log:debug("Completed item", name)
			local list = buf.list
			self._prop_buf[prop][timestamp] = nil
			buf = nil

			self:publish_prop_list(prop, list, timestamp)
		end)
	end

	buf.list[tag_name] = value

	for k, v in pairs(self._inputs_map) do
		if not buf.list[k] then
			return
		end
	end
	buf.completed = true
	--log:debug("Completed item", prop)
	sys:wakeup(buf.id)
end

local prop_map = {
	RDATA = 'Grt',
	MIN = 'TenMins',
	HOUR = 'Hour',
	DAY = 'Day',
}

local time_map = {
	RDATA = 'Grt',
	MIN = 'TenMinsCOU',
	HOUR = 'HourCOU',
	DAY = 'DayCOU',
}

local topic_map = {
	RDATA = 'grt',
	MIN = 'tenminscou',
	HOUR = 'hourcou',
	DAY = 'daycou',
}

function app:publish_prop_list(prop, list, timestamp)
	local datas = {}
	local now = math.floor(timestamp)
	local name = prop_map[prop]
	local time_name = time_map[prop]

	datas[time_name..'_Time'] = os.date('%F %T', now)
	datas[time_name..'_ID'] = now

	for k, v in pairs(list) do
		if prop == 'RDATA' then
			datas[name..'_'..k] = v.value
		else
			datas[name..'COU_'..k] = v.cou
			datas[name..'AVG_'..k] = v.avg
		end
	end
	local topic = 'inputs/'..topic_map[prop]

	local data = {
		datas = datas,
		time_utc = now,
		time_str = os.date("%F %T", now)
	}
	--print(cjson.encode(data))

	return self:publish(topic, cjson.encode(data), 1, true)
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
	return self:publish(self._mqtt_id.."/event", cjson.encode({sn, event, timestamp} ), 1, true)
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
	return self:publish(self._mqtt_id.."/stat", cjson.encode(msg), 1, true)
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
	self:publish(self._mqtt_id..'/result/output', cjson.encode(data), 1, true)
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

function app:on_output(app_src, sn, output, prop, value, timestamp)
	if sn ~= self._dev_sn then
		return nil, "Device Serial Number incorrect!"
	end
	if prop ~= 'value' then
		return nil, "Only value property is supported"
	end
	local setting = self._settings_map[output]
	if not setting then
		return nil, "Output not found"
	end

	local sys = self:sys_api()
	local conf = sys:get_conf()
	conf.settings = conf.settings or {}

	self._value_map[output] = { value = value, timestamp = ioe.time() }
	self._dev:set_input_prop(output, 'value', value)
	self._dev:set_input_prop(setting.hj212, 'value', value)
	for _, v in ipairs(conf.settings) do
		if v.name == output then
			v.value = tostring(value)
			sys:set_conf(conf)
			return true
		end
	end
	table.insert(conf.settings, {name=output, value=tostring(value)})
	sys:set_conf(conf)
	return true
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
