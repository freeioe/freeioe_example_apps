local class = require 'middleclass'
local concat_utils = require 'app.utils.concat'

local calc = class("CALC_FUNCION_MENG_LI_MT")

function calc:initialize(app, dev, input, enable_sub)
	self._app = app
	self._dev = dev
	self._input = input
	self._enable_sub = enable_sub
	self._ns = 1
	self._i_list = {
		1898,
		1913,
		1914,
		1915,
		1916,
		1917,
		1918,
		1919,
		1920,
		1921
	}
	self._nodes = {}
	self._cu = concat_utils:new(function(values)
		self:set_input_values(values)
	end, true, 200)

	for i, v in ipairs(self._i_list) do
		self._cu:add(i)
	end
end

function calc:set_input_values(values)
	local str = string.pack('<I2I2I2I2I2I2I2I2I2I2', table.unpack(values))
	local ei = string.find(str, string.byte(0), 1, true)
	if ei then
		str = string.sub(str, 1, ei - 1)
	end
	self._dev:set_input_prop(self._input.name, 'value', str)
end

function calc:start(ua_client)
	self._client = ua_client
	if self._enable_sub then
		local inputs = {}
		for i, ni in ipairs(self._i_list) do
			inputs[#inputs + 1] = {
				index = i,
				ns = self._ns,
				i = ni,
				vt = 'int'
			}
		end
		self._inputs = inputs
		-- Subscribe nodes
		local r, err = ua_client:create_subscription(inputs, function(input, data_value)
			local value = ua_client:parse_value(data_value, input.vt)
			--local ts = data_value.sourceTimestamp:asDateTime() / 10000000
			self._cu:update(input.index, value)
		end)
	else
		---get opcua node
		for _, ni in ipairs(self._i_list) do
			local node = ua_client:get_node(self._ns, ni)
			assert(node)
			table.insert(self._nodes, node)
		end
	end
end

function calc:stop()
	--TODO: unsubscribe
end

function calc:run()
	local app = self._app
	if not app:connected() then
		-- offline
		return self._dev:set_input_prop(self._input.name, 'value', '')
	end

	if not self._enable_sub then
		local values = {}
		for i, node in ipairs(self._nodes) do
			local value = self._client:read_value(node, 'int')
			assert(value)
			values[i] = value
		end
		self:set_input_values(values)
	end
end

return calc
