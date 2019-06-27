local class = require 'middleclass'
local opcua = require 'opcua'

local app = class("FREEIOE_OPCUA_CLIENT_APP")
app.static.API_VER = 1

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = sys:data_api()
	self._log = sys:logger()
	self._connect_retry = 1000
	self._input_count_in = 0
	self._input_count_out = 0
end

local default_vals = {
	int = 0,
	string = '',
}

local function create_var(idx, devobj, input, device)
	local var, err = devobj:getChild(input.name)
	if var then
		var.description = opcua.LocalizedText.new("zh_CN", input.desc)
		return var
	end
	local attr = opcua.VariableAttributes.new()
	attr.displayName = opcua.LocalizedText.new("zh_CN", input.name)
	if input.desc then
		attr.description = opcua.LocalizedText.new("zh_CN", input.desc)
	end

	local current = device:get_input_prop(input.name, 'value')
	local val = input.vt and default_vals[input.vt] or 0.0
	attr.value = opcua.Variant.new(current or val)

	--[[
	attr.writeMask = opcua.WriteMask.ALL
	attr.userWriteMask = opcua.WriteMask.ALL
	]]
	attr.accessLevel = opcua.AccessLevel.READ ~ opcua.AccessLevel.WRITE ~ opcua.AccessLevel.STATUSWRITE
	--attr.userAccessLevel = opcua.AccessLevel.READ ~ opcua.AccessLevel.READ ~ opcua.AccessLevel.STATUSWRITE
	
	--return devobj:addVariable(opcua.NodeId.new(idx, input.name), input.name, attr)
	return devobj:addVariable(opcua.NodeId.new(idx, 0), input.name, attr)
end

local function set_var_value(var, value, timestamp, quality)
	local val = opcua.DataValue.new(opcua.Variant.new(value))
	val.status = quality
	local tm = opcua.DateTime.fromUnixTime(math.floor(timestamp)) +  math.floor((timestamp%1) * 100) * 100000
	val.sourceTimestamp = tm
	var.dataValue = val
end

function app:is_connected()
	if self._client then
		return true
	end
end

function app:create_device_node(sn, props)
	if not self:is_connected() then
		return
	end

	local client = self._client
	local log = self._log
	local idx = self._idx
	local nodes = self._nodes
	local device = self._api:get_device(sn)

	-- 
	local objects = client:getObjectsNode()
	local namespace = self._conf.namespace or "http://freeioe.org"
	local idx, err = client:getNamespaceIndex(namespace)
	if not idx then
		log:warning("Cannot find namespace", err)
		return
	end
	local devobj, err = objects:getChild(idx..":"..sn)
	if not devobj then
		local attr = opcua.ObjectAttributes.new()
		attr.displayName = opcua.LocalizedText.new("zh_CN", "Device "..sn)
		devobj, err = objects:addObject(opcua.NodeId.new(idx, sn), sn, attr)
		if not devobj then
			log:warning('Create device object failed, error', err)
			return
		else
			log:debug('Device created', devobj)
		end
	else
		log:debug("Device object found", devobj)
	end

	local node = nodes[sn] or {
		idx = idx,
		device = device,
		devobj = devobj,
		vars = {}
	}
	local vars = node.vars
	for i, input in ipairs(props.inputs) do
		local var = vars[input.name]
		if not var then
			local var = create_var(idx, devobj, input, device)
			vars[input.name] = var
		else
			var.description = opcua.LocalizedText.new("zh_CN", input.desc)
		end
	end
	nodes[sn] = node
end

function app:on_add_device(app, sn, props)
	if not self:is_connected() then
		return
	end
	return self:create_device_node(sn, props)
end

function app:on_mod_device(app, sn, props)
	if not self:is_connected() then
		return
	end

	local node = self._nodes[sn]
	local idx = self._idx

	if not node or not node.vars then
		return on_add_device(app, sn, props)
	end

	local vars = node.vars
	for i, input in ipairs(props.inputs) do
		local var = vars[input.name]
		if not var then
			vars[input.name] = create_var(idx, node.devobj, input, node.device)
		else
			var.description = opcua.LocalizedText.new("zh_CN", input.desc)
		end
	end
end

function app:on_del_device(app, sn)
	if not self:is_connected() then
		return
	end
	
	local node = self._nodes[sn]
	if not node then
		return
	end
	
	self._client:deleteNode(node.devobj.id)
	self._nodes[sn] = nil
end

function app:on_post_input(app, sn, input, prop, value, timestamp, quality)
	if not self:is_connected() then
		return
	end

	local node = self._nodes[sn]
	if not node or not node.vars then
		log:error("Unknown sn", sn)
		return
	end
	print(sn, input, prop, value)
	local var = node.vars[input]
	if var and prop == 'value' then
		self._input_count_in = self._input_count_in + 1
		local r, err = pcall(set_var_value, var, value, timestamp, quality)
		self._input_count_out = self._input_count_out + 1
		if not r then
			self._log:error("OPC Client failure!", err)
		end
	end
end

function app:on_disconnect()
	self._nodes = {}
	self._client = nil
	self._sys:timeout(self._connect_retry, function() self:connect_proc() end)
	self._connect_retry = self._connect_retry * 2
	if self._connect_retry > 2000 * 64 then
		self._connect_retry = 2000
	end
end

function app:connect_proc()
	self._log:notice("OPC Client start connection!")
	local client = self._client_obj

	local ep = self._conf.endpoint or "opc.tcp://127.0.0.1:4840"
	self._log:info("Client connect endpoint", ep)

	local r, err

	if self._conf.auth then
		self._log:info("Client connect with username&password")
		r, err = client:connect_username(ep, self._conf.auth.username, self._conf.auth.password)
	else
		self._log:info("Client connect without username&password")
		r, err = client:connect(ep)
	end
	if r and r == 0 then
		self._log:notice("OPC Client connect successfully!")
		self._client = client
		self._connect_retry = 2000
		
		local devs = self._api:list_devices() or {}
		for sn, props in pairs(devs) do
			self:create_device_node(sn, props)
		end
	else
		local err = err or opcua.getStatusCodeName(r)
		self._log:error("OPC Client connect failure! Error: "..err)
		self:on_disconnect()
	end
end

function app:print_debug()
	while true do
		if self._client then
			if 0 == self._client:getState() then
				self._sys:fork(function()
					self:on_disconnect()
				end)
			end
		end
		--print(self._input_count_in, self._input_count_out)
		self._sys:sleep(2000)
	end
end

function app:load_encryption(conf)
	local sys = self._sys

	local securityMode = nil
	if (conf.encryption.mode) then
		if mode == 'SignAndEncrypt' then
			securityMode = opcua.UA_MessageSecurityMode.UA_MESSAGESECURITYMODE_SIGNANDENCRYPT
		end
		if mode == 'Sign' then
			securityMode = opcua.UA_MessageSecurityMode.UA_MESSAGESECURITYMODE_SIGN
		end
		if mode == 'None' then
			securityMode = opcua.UA_MessageSecurityMode.UA_MESSAGESECURITYMODE_NONE
		end
	end

	local cert_file = sys:app_dir()..(conf.encryption.cert or "certs/cert.der")
	local key_file = sys:app_dir()..(conf.encryption.key or "certs/key.der")

	local cert_fn = "certs/certt.der"
	if conf.encryption.cert and string.len(conf.encryption.cert) > 0 then
		cert_fn = conf.encryption.cert
	end
	local cert_file = sys:app_dir()..cert_fn

	local key_fn = "certs/key.der"
	if conf.encryption.key and string.len(conf.encryption.key) > 0 then
		key_fn = conf.encryption.key
	end

	local key_file = sys:app_dir()..key_fn

	return {
		cert = cert_file,
		key = key_file,
		mode = securityMode,
	}
end

function app:start()
	self._nodes = {}

	local conf = self._conf
	local sys = self._sys
	local client = nil

	if conf.encryption then
		local cp = self:load_encryption(conf)
		self._log:info("Create client with entryption", cp.mode, cp.cert, cp.key)
		client = opcua.Client.new(cp.mode, cp.cert, cp.key)
	else
		self._log:info("Create client without entryption.")
		client = opcua.Client.new()
	end

	local config = client.config
	config:setTimeout(5000)
	config:setSecureChannelLifeTime(10 * 60 * 1000)

	local app_uri = conf.app_uri or "urn:freeioe:opcuaclient"
	config:setApplicationURI(app_uri)

	self._client_obj = client

	self._sys:fork(function() self:print_debug() end)
	self._sys:fork(function() self:connect_proc() end)
	self._api:set_handler({
		on_add_device = function(app, sn, props)
			return self:on_add_device(app, sn, props)
		end,
		on_del_device = function(app, sn)
			return self:on_del_device(app, sn)
		end,
		on_mod_device = function(app, sn, props)
			return self:on_mod_device(app, sn, props)
		end,
		on_input = function(app, sn, input, prop, value, timestamp, quality)
			return self._sys:post('input', app, sn, input, prop, value, timestamp, quality)
		end,
	}, true)

	return true
end

function app:close(reason)
	print(self._name, reason)
	self._client = nil
	if self._client_obj then
		self._nodes = {}
		self._client_obj:disconnect()
		self._client_obj = nil
	end
end

function app:run(tms)
	return 1000
end

return app

