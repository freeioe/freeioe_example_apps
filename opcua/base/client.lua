--- 导入需求的模块
local opcua = require 'opcua'
local class = require 'middleclass'

local client = class("APP_OPCUA_CLIENT_BASE")

function client:initialize(app, conf)
	self._app = app
	self._log = app._log
	self._sys = app._sys

	self._conf = conf

	--- All callback from opcua module will run as coroutine task
	self._co_tasks = {}

	--- Subscription id to input object map
	self._sub_map = {}
	--- whether the subscription node has received publish or not
	self._sub_map_node = {}

	self._closing = nil
	self._renew = nil
end

function client:connected()
	return self._client ~= nil
end

---
-- Get the objects node (ns=0, i=85)
--
function client:get_objects_node()
	if not self._client then
		return nil, "Not connected"
	end
	return self._client:getObjectsNode()
end

---
-- Get the namespace index (number) by specified namespace string
-- e.g. http://opcfoundation.org/UA/ which is 0
--
function client:get_namespace_index(namespace)
	if not self._client then
		return nil, "Not connected"
	end
	return self._client:getNamesapceIndex(namespace)
end

--- Get the specified child from node by child_name
--  The child_name is <namespace id>:<browse name>
--  and you cloud append more child_name for deep finding
function client:get_child(node, child_name, ...)
	if not self._client then
		return nil, "Not connected"
	end
	return node:getChild(child_name, ...)
end

function gen_node_id(ns, i, itype)
	local id = nil
	if itype == nil or itype == 'auto' then
		id = opcua.NodeId.new(ns, i)
	else
		if itype == 'hex' then
			id = opcua.NodeId.new(ns, basexx.from_hex(i))
		elseif itype == 'base64' then
			id = opcua.NodeId.new(ns, basexx.from_base64(i))
		elseif itype == 'guid' or itype == 'uuid' then
			id = opcua.NodeId.new(ns, opcua.Guid.new(i))
		elseif itype == 'number' then
			id = opcua.NodeId.new(ns, tonumber(i))
		elseif itype == 'string' then
			id = opcua.NodeId.new(ns, tostring(i))
		else
			id = opcua.NodeId.new(ns, i)
		end
	end
	return id
end

function client:call_method(retry, func, ...)
	local opc_client = self._client
	if not opc_client then
		return nil, "Client is nil"
	end
	local f = opc_client[func]
	if not f then
		return nil, "Client function missing"
	end

	local loop_max = tonumber(retry) or 10
	while loop_max > 0 do
		local r, rr, err = pcall(f, opc_client, ...)
		if not r then
			--print(r, rr, err)
			return nil, rr
		end

		if rr ~= nil then
			return rr
		end

		if err ~= 'BadInvalidState' and err ~= 'BadConnectionClosed' then
			--print('RETTTT', err)
			return nil, err
		end

		if not self._opc_run(200) then
			--print('AAAAAAAAAAAAAAAAA')
			return nil, "OPC Client error in retry!!"
		end
		loop_max = loop_max - 1
	end

	return nil, "Method retry failed!!"
end

function client:get_node(ns, i, itype)
	local opc_client = self._client

	if not opc_client then
		self._log:warning('no opc client', ns, i)
		return nil
	end

	-- Make sure all other functions are working well
	self._sys:sleep(0)

	local id = gen_node_id(ns, i, itype)
	local obj, err
	local loop_max = 10
	while loop_max > 0 do
		obj, err = opc_client:getNode(id)
		if err ~= 'BadInvalidState' and err ~= 'BadConnectionClosed' then
			break
		end

		self._log:trace("DIRK:retry the reading.....")
		if not self._opc_run(200) then
			break
		end
		loop_max = loop_max - 1
	end
	if not obj then
		self._log:warning("Cannot get OPCUA node", ns, i, err)
	else
		self._log:debug('got input node', obj, ns, i)
	end
	return obj, err
end

function client:get_node_by_id(id)
	local obj, err
	local loop_max = 10
	while loop_max > 0 do
		obj, err = self._client:getNode(id)
		if err ~= 'BadInvalidState' and err ~= 'BadConnectionClosed' then
			break
		end
		self._log:trace("DIRK:retry the reading.....")

		if not self._opc_run(100) then
			break
		end
		loop_max = loop_max - 1
	end
	if not obj then
		self._log:warning("Cannot get OPCUA node", id.ns, id.index, err)
	else
		self._log:debug('got input node', obj, id.ns, id.index)
	end
	return obj, err
end

function client:read_value(node, vt)
	self._log:debug('reading node', node, vt, node and node.id)
	if not node then
		return nil
	end
	self._sys:sleep(0)

	local dv = node.dataValue

	return self:parse_value(dv, vt)
end

local value_type_map = {
	boolean = true,
	int8 = true,
	uint8 = true,
	int16 = true,
	uint16 = true,
	int32 = true,
	uint32 = true,
	int64 = true,
	uint64 = true,
	float = true,
	double = true
}

function client:write_value_ex(node, vt, data_type, val)
	self._log:debug('writing node', node, vt, node and node.id)
	local val = assert(val, "value is missing")
	if vt == 'int' then
		val = math.floor(tonumber(val))
	elseif vt == 'float' then
		val = tonumber(val)
	else
		val = tostring(val)
	end
	if not val then
		return nil, "Value incorrect!!"
	end

	assert(value_type_map[data_type], "Value Type: "..data_type.." not supported!")

	local f = opcua.Variant[data_type]
	assert(f, "Value Type: "..data_type.." not supported!")

	if opcua.VERSION and tonumber(opcua.VERSION) >= 1.3 then
		return node:set_Value(f(val))
	else
		--node.dataValue = opcua.DataValue.new(f(val))
		node.value = f(val)
	end

	return true
end

function client:write_value(node, vt, val)
	self._log:debug('writing node', node, vt, node and node.id)
	local val = assert(val, "value is missing")
	if vt == 'int' then
		val = math.floor(tonumber(val))
	elseif vt == 'float' then
		val = tonumber(val)
	else
		val = tostring(val)
	end
	if not val then
		return nil, "Value incorrect!!"
	end

	if opcua.VERSION and tonumber(opcua.VERSION) >= 1.3 then
		local node_dataType, err = node:get_DataType()
		if node_dataType == nil then
			return nil, err
		end
		local dt_name = opcua.get_node_data_value_type(node_dataType)
		local f = opcua.Variant[dt_name]
		if not f then
			return nil, "Value data type: "..dt_name.." not supported!"
		end
		return node:set_Value(f(val))
	else
		--- Write the value to node
		--node.dataValue = opcua.DataValue.new(opcua.Variant.new(val))
		node.value = opcua.Variant.new(val)
	end

	return true
end

function client:parse_value(data_value, vt)
	local dv = data_value

	--- Latest opcua binding support asValue function
	if dv.value.asValue then
		local value, err = dv.value:asValue()
		if value == nil then
			--self._log:debug('asValue failed', err)
			return nil, err
		end

		if vt == 'int' then
			if type(value) == 'boolean' then
				value = value and 1 or 0
			end
			value = tonumber(value)
			if value then
				return math.floor(value)
			end
		end

		if vt == 'string' then
			value = tostring(value)
			if value then
				return value
			end
		end

		--- float
		value = tonumber(value)
		if value then
			return value
		else
			return nil, "Convert to number failed"
		end
	end

	if vt == 'int' then
		local value = dv.value:isNumeric() and dv.value:asLong() or dv.value:asString() or dv.value:asDateTime()
		if not value then
			return nil, "Value type incorrect"
		end

		value = tonumber(value)
		if not value then
			return nil, "Cannot convert to number"
		end

		return math.floor(value), dv.sourceTimestamp, dv.serverTimestamp
	end

	if vt == 'string' then
		local value = dv.value:asString() or dv.value:asDateTime()
		return value, dv.sourceTimestamp, dv.serverTimestamp
	end

	local value = dv.value:isNumeric() and dv.value:asDouble() or dv.value:asString() or dv.value:asDateTime()
	if not value then
		return nil, "Value type incorrect"
	end

	value = tonumber(value)
	if not value then
		return nil, "Cannot convert to number"
	end

	return value, dv.sourceTimestamp, dv.serverTimestamp
end

function client:on_connected()
	self._log:debug("default on connected callback")
	return true
end

function client:on_disconnected()
	self._log:debug("default on disconnected callback")
end

---
-- 连接处理函数
function client:connect_proc()
	local client = self._client_obj
	local conf = self._conf
	local sys = self._sys
	local log = self._log

	log:notice("OPC Client start connection!")

	if opcua.VERSION and tonumber(opcua.VERSION) >= 1.2 then
		local client_session = nil
		client:setStateCallback(function(cli, channel_state, session_state, connect_status)
			table.insert(self._co_tasks, function()
				self._log:trace("Client state sss:", channel_state, ' ss:', session_state, ' cs:', connect_status, cli)
				if self._client_obj ~= cli then
					self._log:error("Error client object")
					return
				end
				if session_state == opcua.UA_SessionState.CREATED then
					self._log:trace("Session state created!")
				elseif session_state == opcua.UA_SessionState.ACTIVATED then
					if not client_session then
						client_session = true
						return self:on_connected()
					end
				elseif session_state == opcua.UA_SessionState.CLOSED then
					if client_session then
						client_session = nil
						return self:on_disconnected()
					end
				else
					self._log:trace("Not handled state", state)
				end
			end)
		end)
	else
		log:warning("OPCUA extension module needs to be upgraded!!!")
		client:setStateCallback(function(cli, state)
			table.insert(self._co_tasks, function()
				self._log:trace("Client state changed to", state, cli)
				if self._client_obj ~= cli then
					self._log:error("Error client object")
					return
				end
				if state == opcua.UA_ClientState.DISCONNECTED then
					return self:on_disconnected()
				elseif state == opcua.UA_ClientState.SESSION_DISCONNECTED then
					return self:on_disconnected()
				elseif state == opcua.UA_ClientState.CONNECTED then
					return self:on_connected()
				elseif state == opcua.UA_ClientState.SESSION then
					return self:on_connected()
				end
			end)
		end)
	end

	local ep = conf.endpoint or "opc.tcp://127.0.0.1:4840"
	--local ep = conf.endpoint or "opc.tcp://172.30.0.187:55623"
	--local ep = conf.endpoint or "opc.tcp://192.168.0.100:4840"
	log:info("Client connect endpoint", ep)

	local connect_opc = function()
		local r, err
		if conf.auth then
			if string.len(conf.auth.username or '') == 0 or string.len(conf.auth.password or '') == 0 then
				log:error("Cannot using empty username or password")
				return false, "empty username/password"
			end
			if not self._client then
				log:info("Client connect with username&password", conf.auth.username, conf.auth.password)
			end
			r, err = client:connect_username(ep, conf.auth.username, conf.auth.password)
		else
			if not self._client then
				log:info("Client connect without username&password")
			end
			r, err = client:connect(ep)
		end

		if r and r == 0 then
			if not self._client then
				log:notice("OPC Client connect successfully!")
				self._client = client

				return true
			else
				return true
			end
		else
			err = err or opcua.getStatusCodeName(r)
			if self._client then
				log:error("OPC Client connect failure!", err)
				self._client = nil
			end
			if err == 'BadInternalError' then
				log:error("OPC Client connect internal failure!", err)
				self._renew = true
			end
			return false, err
		end
	end

	self._opc_run = function(time_ms)
		if self._closing then
			return true
		end
		--- Connection OK
		local r, err = connect_opc()
		if not r then
			return false, err
		end
		if self._client and self._client_obj then
			--[[
			local start = opcua.DateTime.nowMonotonic()
			--log:debug('_opc_run 1', start, os.time())
			while (opcua.DateTime.nowMonotonic() - start) < 50000 do
				--- Client object run
				self._client_obj:run_iterate(5)
			end
			]]--
			self._client_obj:run_iterate(time_ms or 5)
			--- FreeIOE sleep
			sys:sleep(0)
			--log:debug('_opc_run 2', opcua.DateTime.nowMonotonic(), os.time())
			return true
		end
		return false, "Client lost!"
	end

	local connect_delay = 1000
	while self._closing == nil and client and self._client_obj and not self._renew do
		-- call connect is save when client connected according to open62541 example
		local r, err = connect_opc()
		if not r then
			--- Connection Failed
			log:error("OPC Client disconnected!", err)
			if not self._closing and not self._renew then
				sys:sleep(connect_delay)
			end
			connect_delay = connect_delay * 2
			if connect_delay > 64000 then
				connect_delay = 1000
			end
		else
			--- Connection OK
			sys:sleep(10)

			connect_delay = 1000
			--- Client object run
			self._client_obj:run_iterate(50)

			--- Trigger all coroutine tasks
			for _, v in ipairs(self._co_tasks) do
				--- Break all co tasks when closing or renew action is required
				if self._closing or self._renew then
					break
				end
				--[[
				-- Do not use fork as we want the coroutine run with orders
				sys:fork(function()
					v(self)
				end)
				]]--
				v(self)
				if not self._opc_run() then
					break
				end
			end
			self._co_tasks = {}
		end
	end

	log:notice("OPCUA connection closing...")
	client:disconnect()
	log:notice("OPCUA connection closed")

	if self._closing then
		self._renew = nil -- reset renew flag
		sys:wakeup(self._closing)
	else
		if self._renew then
			self._renew = nil
			sys:timeout(2000, function()
				self:connect()
			end)
		end
	end
end

function client:load_encryption(conf)
	local securityMode = nil
	if (conf.encryption.mode) then
		local mode = conf.encryption.mode
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

	local sys = self._sys
	local cert_file = sys:app_dir()..(conf.encryption.cert or "certs/cert.der")
	local key_file = sys:app_dir()..(conf.encryption.key or "certs/key.der")

	return {
		cert = cert_file,
		key = key_file,
		mode = securityMode,
	}
end

function client:create_client_obj()
	local conf = self._conf
	--conf.modal = conf.modal or default_modal

	local client_obj = nil

	if conf.encryption then
		local cp = self:load_encryption(conf)
		self._log:info("Create client with encryption", cp.mode, cp.cert, cp.key)
		client_obj = opcua.Client.new(cp.mode, cp.cert, cp.key)
	else
		self._log:info("Create client without encryption.")
		client_obj = opcua.Client.new()
	end

	local config = client_obj.config
	config:setTimeout(5000)
	config:setSecureChannelLifeTime(10 * 60 * 1000)

	local client_uri = conf.client_uri or "urn:freeioe:opcuaclient"
	config:setApplicationURI(client_uri)

	return client_obj
end

--- 应用启动函数
function client:connect()
	--- Create client object
	self._client_obj = self:create_client_obj()

	--- 发起OpcUa连接
	self._sys:fork(function() self:connect_proc() end)

	return true
end

function client:disconnect()
	self._closing = {}
	self._sys:wait(self._closing)
	self._closing = nil
	return true
end

function client:create_subscription(inputs, callback)
	if not self._client then
		return nil, "Client not connected"
	end

	self._log:debug("Create subscription start!!!!")

	local sub_id, err = self._client:createSubscription(function(mon_id, data_value, sub_id)
		local m = self._sub_map[sub_id]
		if not m then
			return
		end
		local input = m[mon_id]
		if input then
			self._sub_map_node[input] = nil
			--- TODO: Using better way to implement this co tasks
			local now = self._sys:time()
			self._log:debug("Subscription callback", sub_id, input.name, now)
			table.insert(self._co_tasks, function()
				local r, err = xpcall(callback, debug.traceback, input, data_value, now)
				if not r then
					self._log:warning("Failed to call callback", err)
				end
			end)
		end
	end)

	if not sub_id then
		return nil, err
	end

	local sub_map = {}
	local failed = {}
	for _, v in ipairs(inputs) do
		if not self._opc_run() then
			return nil, "Client disconnected"
		end
		--self._sys:sleep(0)

		--- Get namespace index
		local id = gen_node_id(v.ns, v.i, v.itype)
		v.node_id = id

		if v.i ~= -1 then
			--local mon_id, err = self._client:subscribeNode(sub_id, id)
			local mon_id, err = self:call_method(10, 'subscribeNode', sub_id, id)
			if mon_id then
				self._log:debug("Subscribe node", v.ns, v.i, sub_id, mon_id)
				sub_map[mon_id] = v
				self._sub_map_node[v] = true
			else
				self._log:warning("Failed to subscribe node", v.ns, v.i, err)
				table.insert(failed, v)
			end
		else
			self._log:warning("Node index -1 is skipped!!")
		end

		--[[
		local node, err = self:get_node_by_id(id)
		if node then
			local mon_id, err = self._client:subscribeNode(sub_id, id)
			if mon_id then
			self._log:warning("Subscribe node", v.ns, v.i, sub_id, mon_id)
				sub_map[mon_id] = v
			else
				self._log:warning("Failed to subscribe node", v.ns, v.i, err)
				table.insert(failed, v)
			end

			local r, err = xpcall(callback, debug.traceback, v, node.dataValue)
			if not r then
				self._log:warning("Failed to call callback", err)
			end
		end
		]]--
	end

	--- All not read will push to co task queue
	for _, v in ipairs(inputs) do
		table.insert(self._co_tasks, function()
			if not self._sub_map_node[v]  then
				return
			end
			local node = self:get_node_by_id(v.node_id)
			if node then
				if opcua.VERSION and tonumber(opcua.VERSION) >= 1.3 then
					local dv, err = node:get_DataValue()
					if dv ~= nil then
						local now = self._sys:time()
						self._log:debug("Subscription read initial value", sub_id, v.name, now)
						local r, err = xpcall(callback, debug.traceback, v, dv, now)
						if not r then
							self._log:warning("Failed to call callback", err)
						end
					else
						self._log:warning("Failed to read dataValue", err)
					end
				else
					local now = self._sys:time()
					self._log:debug("Subscription read initial value", sub_id, v.name, now)
					local r, err = xpcall(callback, debug.traceback, v, node.dataValue, now)
					if not r then
						self._log:warning("Failed to call callback", err)
					end
				end
			end
		end)
	end

	self._log:debug("Create subscription end!!!!")

	self._sub_map[sub_id] = sub_map
	return #failed == 0, failed
end

--- 返回应用对象
return client

