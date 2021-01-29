local ioe = require 'ioe'
local csv_tpl = require 'csv_tpl'
local conf_helper = require 'app.conf.helper'
local tsdb_siri = require 'tsdb.siridb'
local tsdb_prom = require 'tsdb.prometheus'
local base = require 'app.base'

local app = base:subclass("FREEIOE.APP.OTHER.SIM_TPL")
app.static.API_VER = 8

function app:on_init()
	self._devs = {}
end

function app:on_start()
	local sys = self:sys_api()
	local log = self:log_api()
	local conf = self:app_conf()
	conf.devs = conf.devs or {}

	if ioe.developer_mode() and #conf.devs == 0 then
		conf.devs = {{ sn = "tsdb_sim", name = "sim", desc = "sim device", tpl = "test" }}
	end

	csv_tpl.init(sys:app_dir())	
	local helper = conf_helper:new(sys, conf)
	helper:fetch() --- Fetch templates

	--- Default is with gateway sn prefix
	local with_prefix = conf.dev_sn_prefix ~= nil and conf.dev_sn_prefix or true

	for _, v in ipairs(helper:devices()) do
		assert(v.sn and v.name and v.tpl)

		local dev_sn = with_prefix and sys:id()..'.'..v.sn or v.sn
		log:debug("Loading template file", v.tpl)
		local tpl, err = csv_tpl.load(v.tpl, function(...) log:error(...) end)
		if not tpl then
			log:error("Failed loading template file", err)
		else
			self:create_device(dev_sn, v, tpl)
		end
	end

	self._cycle = tonumber(conf.cycle) or 5000 -- ms
	if self._cycle < 10 then
		self._cycle = 10
	end

	self._tsdb = {
		siri = tsdb_siri:new('test'),
		prom =  tsdb_prom:new('test')
	}
	self._tsinfo = {}

	for name, db in pairs(self._tsdb) do
		assert(db:init())
		self._tsinfo[name] = {
			count = 0,
			cost = 0,
			data = {}
		}
	end

	return true
end

function app:create_device(dev_sn, info, tpl)
	local api = self:data_api()
	local meta = api:default_meta()
	meta.name = 'Simulation'
	meta.description = info.desc or "Simuation device"
	meta.series = 'freeioe.other.sim_tpl'
	meta.inst = info.name

	local inputs = {}
	local outputs = {}
	local tpl_inputs = {}
	local tpl_outputs = {}
	for _, v in ipairs(tpl.props) do
		if string.find(v.rw, '[Rr]') then
			inputs[#inputs + 1] = {
				name = v.name,
				desc = v.desc,
				vt = v.vt,
				unit = v.unit,
			}
			tpl_inputs[#tpl_inputs + 1] = v
		end
		if string.find(v.rw, '[Ww]') then
			outputs[#outputs + 1] = {
				name = v.name,
				desc = v.desc,
				unit = v.unit,
			}
			tpl_outputs[#tpl_outputs + 1] = v
		end

		v.method_func = assert(load('return '..v.method, v.name, 't', {
			RANDOM = function(...)
				return math.random(...)
			end
		}))
	end
	local dev = api:add_device(dev_sn, meta, inputs, outputs)
	self._devs[info.sn or dev_sn] = {
		dev = dev,
		tpl = tpl,
		inputs = tpl_inputs,
		outputs = tpl_outputs,
	}
	self._stat = dev:stat('port')
	self._last_print = ioe.now()
end

function app:on_run(tms)
	for sn, dev in pairs(self._devs) do
		self:gen_device_data(dev, sn)
	end

	for k, info in pairs(self._tsinfo) do
		local start = ioe.hpc()
		local db = self._tsdb[k]
		if #info.data > 0 then
			local start = ioe.hpc()
			db:insert_list(info.data)
			local ms = (ioe.hpc() - start) / 1000000
			--log:debug(k..' insert time:'..ms..' ms')
			info.cost = info.cost + ms
			info.count = info.count + #info.data
			info.data = {}
		end
	end
	
	self._stat:set('status', math.random(0, 1))

	if ioe.now() - self._last_print >= 60 * 1000 then
		local log = self:log_api()
		for name, db in pairs(self._tsinfo) do
			local avg = db.count > 0 and db.cost / db.count or 0
			log:info(string.format('DB:%s COUNT:%d, COST:%f ms AVG:%f ms', name, db.count, db.cost, avg))
		end
		self._last_print = ioe.now()
	end
	return self._cycle
end

function app:save_input_prop(dev, input, vt, value)
	local log = self:log_api()
	local name = dev..'.'..input..'.'..vt
	local ts = ioe.time()
	--[[
	for k, db in pairs(self._tsdb) do
		local start = ioe.hpc()
		db:insert(name, vt or 'float', value, ts)
		local ms = (ioe.hpc() - start) / 1000000
		--log:debug(k..' insert time:'..ms..' ms')
		self._tsinfo[k].cost = self._tsinfo[k].cost + ms
		self._tsinfo[k].count = self._tsinfo[k].count + 1
	end
	]]--
	for k, v in pairs(self._tsinfo) do
		table.insert(v.data, {name, vt or 'float', value, ts})
	end
end

function app:gen_device_data(dev, sn)
	local sys = self:sys_api()
	local log = self:log_api()
	local now = sys:now() // 1000
	for _, v in ipairs(dev.inputs) do
		if v.last == nil or math.abs(now - v.last) > v.freq then
			local r, val = pcall(v.method_func)
			--log:debug(v.name, v.method, r, val)
			if not r then
				log:error(val)
			else
				v.last_value = v.base + val
				dev.dev:set_input_prop(v.name, 'value', v.last_value)
				self:save_input_prop(sn, v.name, v.vt, v.last_value)
			end
			v.last = now
		else
			dev.dev:set_input_prop(v.name, 'value', v.last_value)
			self:save_input_prop(sn, v.name, v.vt, v.last_value)
		end
	end
end

return app
