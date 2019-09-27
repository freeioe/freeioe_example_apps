local ioe = require 'ioe'
local cjson = require 'cjson.safe'
local base_mqtt = require 'app.base.mqtt'
local telit_helper = require 'telit_helper'

--- 创建应用（名称，最小API版本)
local app = base_mqtt:subclass("_TELIT_CLOUD_MQTT")
app.static.API_VER = 5

function app:on_init()
	local conf = self._conf
	for k, v in pairs(conf.options or {}) do
		conf[k] = v
	end
	self._log:debug("Telit app intialize!!!")
end

function app:on_start()
	local conf = self._conf
	self._log:debug(conf.application_id, conf.application_token, self._sys:id())
	self._def_keys ={}
	for _,v in ipairs(conf.def_keys or {}) do
		self._def_keys[v.sn] = v.thing_key
		self._log:info("Thingkey Map", v.sn, v.thing_key)
	end
	self._def_keys['GL'] = 'freeioe_guolu'
	self._def_key_default = string.lower(conf.def_key_default or 'freeioe_gw')
	self._key_created = {}

	return base_mqtt.on_start(self)
end

function app:mqtt_auth()
	local conf = self._conf
	self._log:debug(conf.application_id, conf.application_token, self._sys:id())
	return {
		client_id = conf.application_id or 'APPLICATION_ID',
		username = self._sys:id(),
		password = conf.application_token or "APPLICATION_TOKEN",
		host = conf.server or "device1-api.10646.cn",
		port = conf.port or "1883",
		clean_session = true
	}
end

function app:subscribe_device(dev_sn)
	local topic = string.format('thing/%s/attribute/toedge', telit_helper.escape_key(dev_sn))
	return self:subscribe(topic, 1)
end

function app:unsubscribe_device(dev_sn)
	local topic = string.format('thing/%s/attribute/toedge', telit_helper.escape_key(dev_sn))
	return self:unsubscribe(topic)
end

function app:find_thing_def_key(sn)
	local sysid = self._sys:id()
	if sysid == sn then
		return self._def_key_default
	end

	local def_key = self._def_keys[sn]

	if not def_key and sysid == string.sub(sn, 1, string.len(sysid)) then
		local ssn = string.sub(sn, string.len(sysid) + 1)
		if string.sub(ssn, 1, 1) == '.' then
			ssn = string.sub(ssn, 2)
		end
		def_key = self._def_keys[ssn]
	end

	return def_key and string.lower(def_key) or nil
end

function app:on_add_device(src_app, sn, props)
	self._log:debug("Telit on_add_device", src_app, sn)

	if not self:connected() then
		return nil, "MQTT not connected!"
	end

	--[[
	if self._key_created[sn] then
		return
	end
	]]--

	local sysid = self._sys:id()
	if sn ~= sysid then
		local def_key = self:find_thing_def_key(sn)
		if not def_key then
			self._log:debug("Device skipped!!", sn)
			return true, "Device skipped!!"
		end

		--[[ thing.create.json ]]--
		local tags = {}
		local tag_map = {}
		for _, input in ipairs(props.inputs) do
			tag_map[input.name] = true
			tags[#tags + 1] = input.name
		end
		for _, output in ipairs(props.outputs or {}) do
			if not tag_map[output.name] then
				tag_map[input.name] = true
				tags[#tags + 1] = output.name
			end
		end
		local params = {
			name = props.meta.name or 'UNKNOWN',
			key = telit_helper.escape_key(sn),
			defKey = def_key,
			desc = props.meta.description or 'UNKNOWN',
			--tags = tags, -- disable tags for now
		}
		local cmd = {
			command = "thing.create",
			params = params,
		}
		local val, err = cjson.encode({cmd=cmd})
		if not val then
			self._log:warning('cjson encode failure. error: ', err)
			return true -- skip this data
		end

		self._log:trace(val)
		self._key_created[sn] = true
		local r, err = self:publish("api", val, 1, false)
		if r then
			return self:subscribe_device(sn)
		end
		return nil, err
	end
	return true
end

function app:on_del_device(src_app, sn)
	self._log:debug("Telit on_del_device")
	self:unsubscribe_device(sn)
	return true
end

function app:on_mod_device(src_app, sn, props)
	self._log:debug("Telit on_mod_device")
	return true
end

function app:format_timestamp(timestamp)
	return string.format("%s.%03dZ", os.date('!%FT%T', timestamp//1), ((timestamp * 1000) % 1000))
end

function app:pack_key(src_app, sn, input, prop)
	if prop ~= 'value' then
		return nil
	end

	local def_key = self:find_thing_def_key(sn)
	if not def_key then
		--- If there is no thing def key then skip device
		return nil
	end

	return sn .. '/'.. input
end

function app:on_publish_devices(devices)
	for sn, props in pairs(devices) do
		self:on_add_device('__fake_name', sn, props)
	end
end

function app:publish_attribute(dev_sn, input, value, timestamp)
	if not self:connected() then
		return nil, "MQTT connection lost!"
	end
--[[ attribute.publish.json ]]--
    local cmd = {
		command = "attribute.publish",
		params = {
			thingKey = telit_helper.escape_key(dev_sn),
			key = telit_helper.escape_key(input),
			value = value,
			ts = self:format_timestamp(timestamp or ioe.time()),
			republish = false
		}
	}
	local val, err = cjson.encode({cmd=cmd})
	if not val then
		self._log:warning('cjson encode failure. error: ', err)
		return true -- skip this data
	end

	self._log:trace(val)
	return self:publish("api", val, 1, false)

end

function app:on_publish_data(key, value, timestamp, quality)
	if not self:connected() then
		return nil, "MQTT connection lost!"
	end

	local sn, input = string.match(key, '^([^/]+)/(.+)$')
	sn = telit_helper.escape_key(sn)
	input = telit_helper.escape_key(input)

	assert(key and sn and input)
    local cmd = {
		command = "property.publish",
		params = {
			thingKey = sn,
			key = input,
			value = value,
			ts = self:format_timestamp(timestamp),
			--corrId = self._mqtt_username,
		}
	}
	local val, err = cjson.encode({cmd=cmd})
	if not val then
		self._log:warning('cjson encode failure. error: ', err)
		return true -- skip this data
	end

	self._log:trace(val)
	return self:publish("api", val, 1, false)
end

--- The implementation for publish data in list (zip compressing required)
function app:on_publish_data_list(val_list)
	assert(val_list)

	local val_count = #val_list
	self._log:trace('publish_data_list begin',  #val_list)

	if val_count == 0 then
		return true
	end

	if not self:connected() then
		self._log:trace('publish_data_list connection not ready!')
		return nil, "MQTT connection lost!"
	end

--[[ property.batch.json ]]--
	local data_list = {}
	local attr_list = {}
	for _, v in ipairs(val_list) do
		local sn, input = string.match(v[1], '^([^/]+)/(.+)$')
		--print(sn, input)
		sn = telit_helper.escape_key(sn)
		input = telit_helper.escape_key(input)

		if type(v[2]) ~= 'string' then
			if not data_list[sn] then
				data_list[sn] = {}
			end
			table.insert(data_list[sn], {
				key = input,
				value = v[2],
				ts = self:format_timestamp(v[3]),
				--corrId = self._mqtt_username,
			})
		else
			if not attr_list[sn] then
				attr_list[sn] = {}
			end
			table.insert(attr_list[sn], {
				key = input,
				value = v[2],
				ts = self:format_timestamp(v[3]),
			})
		end
	end

	for sn, data in pairs(data_list) do
		local cmd = {
			command = "property.batch",
			params = {
				thingKey = sn,
				--key = 'UNKNOW',
				--ts = self:format_timestamp(ioe.time()),
				data = data
			}
		}

		local val, err = cjson.encode({cmd=cmd})
		--print(val)
		if not val then
			self._log:warning('cjson encode failure. error: ', err)
			return true -- skip current datas
		end

		local deflated = self:compress(val)
		local r, err = self:publish("apiz", deflated, 1, false)

		if not r then
			return nil, err
		end
	end

	for sn, data in pairs(attr_list) do
		local cmd = {
			command = "attribute.batch",
			params = {
				thingKey = sn,
				--key = 'UNKNOW',
				--ts = self:format_timestamp(ioe.time()),
				data = data
			}
		}

		local val, err = cjson.encode({cmd=cmd})
		--print(val)
		if not val then
			self._log:warning('cjson encode failure. error: ', err)
			return true -- skip current datas
		end

		local deflated = self:compress(val)
		local r, err = self:publish("apiz", deflated, 1, false)

		if not r then
			return nil, err
		end
	end
	self._log:trace('publish_data_list end!')
	return true
end

function app:on_publish_cached_data_list(val_list)
	local r, err = self:on_publish_data_list(val_list)
	if r then
		return #val_list
	end
	return nil, err
end

-- no return
function app:on_mqtt_connect_ok()
	self._log:debug("Telit on_connect_ok")
	--[[
	self:subscribe('reply', 1)
	self:subscribe('replyz', 1)
	]]--
end

function app:on_mqtt_message(packet_id, topic, payload, qos, retained)
	if topic == 'replyz' then
		local inflated, eof, bytes_in, bytes_out = self:decompress(payload)
		payload = inflated
	end
	self._log:trace('MQTT Message', topic, qos, retained, payload)

	local thing_key_match = '^thing/(%w+)/attribute/toedge$'
	local thing_key = string.match(topic, thing_key_match)
	if thing_key then
		--- Write output
		local id, input, value = string.match(payload, '^([^/]+)/([^/]+)/(.+)$')
		if id and input and value then
			local dev_sn = telit_helper.unescape_key(thing_key)
			input = telit_helper.unescape_key(input)
			local device, err = self._api:get_device(dev_sn)
			if not device then
				self._log:error('Cannot parse payload!')
				return self:on_toedge_result(id, dev_sn, input, -1, err)
			end
			local priv = { id = id, dev_sn = dev_sn, input = input }
			local r, err = device:set_output_prop(input, 'value', value, ioe.time(), priv)
			if not r then
				self._log:error('Set output prop failed!', err)
				return self:on_toedge_result(id, dev_sn, input, -2, err)
			end
			---return self:on_toedge_result(id, dev_sn, input, 0, "done")
			-- return self:on_toedge_result(id, dev_sn, input, -2, err)
		else
			self._log:error('Cannot parse payload!')
		end
	end
end

function app:on_toedge_result(id, dev_sn, input, result, err)
	local value = string.format("%s;%s;%d;%s", id, telit_helper.escape_key(input), result, err)
	return self:publish_attribute(dev_sn, 'todmp', value, ioe.time())
end

function app:on_output_result(app_src, priv, result, err)
	if result then
		return self:on_toedge_result(priv.id, priv.dev_sn, priv.input, 0, "done")
	else
		return self:on_toedge_result(priv.id, priv.dev_sn, priv.input, -99, err)
	end
end

--- 返回应用类对象
return app

