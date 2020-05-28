local class = require 'middleclass'
local ioe = require 'ioe'
local event = require 'app.event'

local map_input = class('CALC_FUNC_MAP_INPUT_CLASSS_LIB')

function map_input:initialize(app, dev, input, enable_sub)
	self._app = app
	self._dev = dev
	self._input = input
	self._enable_sub = enable_sub
	self._log = app._log

	local node_list = {}
	for i, v in ipairs(input.values) do
		--print(v.desc, v.ns, v.i)
		table.insert(node_list, {
			index = i,
			desc = v.desc,
			ns = v.ns,
			i = v.i,
			vt = 'int',
			reverse = v.reverse,
			value = v.value
		})
	end

	self._nodes = node_list
	self._tmp_values = {}
end

function map_input:set_input_values(values)
	local value = nil
	for k, v in pairs(values) do
		local node = self._nodes[k]
		local val = node.reverse and v == 0 or v ~= 0
		if val and (not value or value < node.value) then
			value = node.value
		end
	end
	local sys = self._app._sys
	local now = sys:time()
	if value then
		self._dev:set_input_prop(self._input.name, "value", value, now, 0)
	else
		self._dev:set_input_prop(self._input.name, "value", 0, now, -1)
	end
end

function map_input:on_value_update(node, value, delay)
	local delay = delay or 200
	self._tmp_values[node.index] = value
	local sys = self._app._sys
	if self._update_cancel then
		self._update_cancel()
	end

	self._update_cancel = sys:cancelable_timeout(delay, function()
		self._update_cancel = nil
		local values = self._tmp_values;
		self._tmp_values = {}

		self:set_input_values(values)
	end)
end

function map_input:start(ua_client)
	local client = ua_client
	self._client = client

	if self._enable_sub then
		-- Subscribe nodes
		self._log:debug("Create Subscription for MAP INPUTS")
		local r, err = client:create_subscription(self._nodes, function(node, data_value)
			local value = client:parse_value(data_value, node.vt)
			self._log:debug('MAP INPUT Sub recv', node.desc, node.i, node.vt, value, data_value.value:asString())
			self:on_value_update(node, value)
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

function map_input:run()
	local app = self._app
	if not app:connected() then
		return
	end

	if not self._enable_sub then
		local values = {}
		for i, node in ipairs(self._nodes) do
			local value = self._client:read_value(node, node.vt)
			values[i] = value
		end
		self:set_input_values(values)	
	end
end

function map_input:stop()
	--TODO: UN-SUB nodes
end

return map_input
