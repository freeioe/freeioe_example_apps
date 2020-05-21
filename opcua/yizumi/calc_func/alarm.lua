local class = require 'middleclass'
local ioe = require 'ioe'
local event = require 'app.event'

local alarm = class('CALC_FUNC_ALARM_CLASSS_LIB')

function alarm:initialize(app, dev, nodes, input, enable_sub)
	self._app = app
	self._dev = dev
	self._input = input
	self._enable_sub = enable_sub
	self._log = app._log

	local node_list = {}
	for _, v in ipairs(nodes) do
		table.insert(node_list, {
			ns = v.ns,
			desc = v.desc,
			i = v.i,
			vt = 'int',
			reverse = v.reverse,
			errno = v.errno,
			is_error = v.is_error,
		})
	end

	self._nodes = node_list
	self._alarmed = {}
	self._alarm_on = {}
	self._alarm_off = {}
end

function alarm:set_alarm_value(node, value)
	local bval = node.reverse and value == 0 or value ~= 0

	--print(node.desc, node.i, node.on, bval, value, node.errno)
	if node.on == nil then
		node.on = bval
		if bval then
			self:fire_alarm(node, node.on)
		end
	else
		if node.on ~= bval then
			node.on = bval
			self:fire_alarm(node, node.on)
		end
	end

	self:update_state(node, bval)
end

function alarm:fire_alarm(node, on, delay)
	local delay = delay or 200

	local sys = self._app._sys
	if self._alarm_cancel then
		self._alarm_cancel()
	end

	if on then
		node.on_time = node.on_time or ioe.time()
		table.insert(self._alarm_on, node.errno)
	else
		table.insert(self._alarm_off, {
			alarm_no = node.errno,
			time = ioe.time() - node.on_time	
		})
		--- Clear time stuff
		node.on_time = nil
	end

	self._alarm_cancel = sys:cancelable_timeout(delay, function()
		self._alarm_cancel = nil
		if #self._alarm_on > 0 then
			self._dev:fire_event(event.LEVEL_INFO, event.EVENT_DEV, 'ALARM_ON', {
				alarm_list = self._alarm_on
			})
			self._alarm_on = {}
		end
		if #self._alarm_off > 0 then
			self._dev:fire_event(event.LEVEL_INFO, event.EVENT_DEV, 'ALARM_OFF', {
				alarm_list = self._alarm_off
			})
			self._alarm_off = {}
		end
	end)
end

function alarm:update_state(node, on)
	if not self._input then
		return
	end

	if on then
		self._alarmed[node.errno] = node.is_error
	else
		self._alarmed[node.errno] = nil
	end

	local new_state = 'NONE'
	for k, v in pairs(self._nodes) do
		local alm = self._alarmed[v.errno]
		if alm then
			if alm.is_error == 1 then
				new_state = 'ERROR'
			else
				if new_state ~= 'ERROR' then
					new_state = 'WARNING'
				end
			end
		end
	end
	self._dev:set_input_prop(self._input, 'value', new_state)
end

function alarm:start(ua_client)
	local client = ua_client
	self._client = client

	if self._enable_sub then
		-- Subscribe nodes
		local r, err = client:create_subscription(self._nodes, function(node, data_value)
			local value = client:parse_value(data_value, node.vt)
			self._log:debug('ALARM Sub recv', node.desc, node.i, node.vt, value, data_value.value:asString())
			self:set_alarm_value(node, value)
		end)
	else
		---get opcua node
		for _, node in ipairs(self._nodes) do
			local obj = client:get_node(self._ns, ni)
			assert(obj)
			node.obj = obj
		end
	end
end

function alarm:stop()
	-- TODO: Unsubscribe
end

function alarm:run()
	local app = self._app
	if not app:connected() then
		return
	end

	if not self._enable_sub then
		for i, node in ipairs(self._nodes) do
			local value = self._client:read_value(node, node.vt)
			self:set_alarm_value(node, value)
		end
	end
end


return alarm
