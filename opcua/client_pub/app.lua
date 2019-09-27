local app_base = require 'app.base'
local opcua_client = require 'base.client'

local app = opcua_client:subclass("FREEIOE_OPCUA_CLIENT_APP")
app.static.API_VER = 5

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
		return self._client:connected() 
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
		local r, err = pcall(set_var_value, var, value, timestamp, quality)
		if not r then
			self._log:error("OPC Client failure!", err)
		end
	end
end

function app:on_connected(client)	
	if client ~= self._client then
		return false
	end
	local devs = self._api:list_devices() or {}
	self._nodes = {}
	for sn, props in pairs(devs) do
		self:create_device_node(sn, props)
	end
	return true
end

function app:on_start()
	local conf = self._conf
	local sys = self._sys

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

	self._client = opcua_client:new(self, conf)
	self._client.on_connected = function(client)
		return self:on_connected(client)
	end
	self._client:connect()

	return true
end

function app:close(reason)
	self._nodes = {}
	if self._client then
		self._client:disconnect()
		self._client = nil
	end
end

function app:run(tms)
	return 1000
end

return app

