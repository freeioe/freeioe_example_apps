local class = require 'middleclass'
local ioe = require 'ioe'
local event = require 'app.event'

local alarm = class('CALC_FUNC_ALARM_CLASSS_LIB')

function alarm:initialize(app, dev, nodes, enable_sub)
	self._app = app
	self._dev = dev
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
			errno = v.errno
		})
	end

	self._nodes = node_list
end

function alarm:set_alarm_value(node, value)
	local bval = node.reverse and value == 0 or value ~= 0
	--print(node.desc, node.i, node.on, bval, value)
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
