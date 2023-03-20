local sysinfo = require 'utils.sysinfo'
local base_app = require 'app.base'

local app = base_app:subclass("FREEIOE_DATA_SIM_APP")
app.static.API_VER = 4

function app:initialize(name, sys, conf)
	base_app.initialize(self, name, sys, conf)
	self._devs = {}
end

function app:on_start()
	local dev_count = self._conf.device_count or 4
	local tag_count = self._conf.tag_count or 4

	for d = 1, dev_count do
		local dev_sn = self._sys:id()..'.'..self._name..'_'..d
		local inputs = {}

		local outputs = {}
		for i = 1, tag_count do
			inputs[#inputs + 1] = {
				name = 'tag'..i,
				desc = 'input '..i,
			}
		end

		inputs[#inputs + 1] = {
			name = 'tag_string',
			desc = 'input as string',
			vt = 'string',
		}

		local meta = self._api:default_meta()
		meta.name = "Data Simulation"
		meta.description = "Data Simulation device"
		meta.series = "X"
		local dev = self._api:add_device(dev_sn, meta, inputs)
		table.insert(self._devs, dev)
	end

	return true
end

function app:on_close(reason)
	--print(self._name, reason)
end

function app:on_run(tms)
	local tag_count = self._conf.tag_count or 4
	local run_loop = self._conf.run_loop or 1000 -- ms

	for _, dev in ipairs(self._devs) do
		for i = 1, tag_count do
			dev:set_input_prop('tag'..i, 'value', math.random(0xFFFFFFFF))
		end
		dev:set_input_prop('tag_string', 'value', os.date())

		self._sys:sleep(10)
	end


	return run_loop
end

return app
