--- 导入需求的模块
local app_base = require 'app.base'
local csv_tpl = require 'csv_tpl'
local conf = require 'app.conf'
local timer = require 'utils.timer'
local conn = require 'conn'
local meter = require 'hj212.client.meter'
local station = require 'hj212.client.station'
local tag = require 'hjtag'

--- lua_HJ212_version: 2020-12-15

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_HJ212_APP")
--- 设定应用最小运行接口版本, 7 has new api and lua5.4???
app.static.API_VER = 7

--- 应用启动函数
function app:on_start()
	local sys = self:sys_api()
	local conf = self:app_conf()

	self._rdata_interval = tonumber(conf.rdata_interval) or -1
	self._min_interval = tonumber(conf.min_interval) or 10

	conf.servers = conf.servers or {}
	if #conf.servers == 0 then
		table.insert(conf.servers, {
			name = 'localhost',
			host = '127.0.0.1',
			port = 16000,
			passwd = '123456',
		})
	end

	local tpl_id = conf.tpl
	local tpl_ver = conf.ver
	local tpl_file = 'example'

	if conf.tpls and #conf.tpls >= 1 then
		tpl_id = conf.tpls[1].id
		tpl_ver = conf.tpls[1].ver
	end

	if tpl_id and tpl_ver then
		local capi = sys:conf_api(tpl_id)
		local data, err = capi:data(tpl_ver)
		if not data then
			self._log:error("Failed loading template from cloud!!!", err)
			return false
		end
		tpl_file = tpl_id..'_'..tpl_ver
	end
	self._log:info("Loading template", tpl_file)

	-- 加载模板
	csv_tpl.init(self._sys:app_dir())
	local tpl = csv_tpl.load_tpl(tpl_file, function(...) self._log:error(...) end)

	self._tpl = tpl
	self._devs = {}

	self._station = station:new(conf.system, conf.dev_id)

	local inputs = {}
	local app_inst = self
	for sn, tags in pairs(tpl.devs) do
		local dev = {}
		local tag_list = {}
		for _, prop in ipairs(tags) do
			inputs[#inputs + 1] = {
				name = prop.name,
				desc = prop.desc,
				unit = prop.unit,
				vt = prop.vt
			}
			if dev[prop.input] then
				table.insert(dev[prop.input], prop)
			else
				dev[prop.input] = {prop}
			end

			local tag = tag:new(sn, prop.name)
			local p_name = prop.name
			tag:set_value_callback(function(value, timestamp)
				local dev = app_inst._dev
				if not dev then
					return
				end
				dev:set_input_prop(p_name, 'value', value, timestamp)
			end)

			tag_list[prop.name] = tag
		end
		self._devs[sn] = dev
		self._station:add_meter(meter:new(sn, {}, tag_list))
	end

	local sys_id = self._sys:id()

	local meta = self._api:default_meta()
	meta.name = 'HJ212' 
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'HJ212 Smart Device' 
	meta.series = 'N/A'

	local dev_sn = sys_id..'.HJ212_'..self:app_name()
	self._dev_sn = dev_sn

	self._dev = self._api:add_device(dev_sn, meta, inputs)

	--- initialize connections
	self._clients = {}
	for _, v in ipairs(conf.servers) do
		local client = conn:new(self, v, self._station)
		local r, err = client:start()
		if not r then
			self._log:error("Start connection failed", err)
		end
		table.insert(self._clients, client)
	end

	--- Start timers
	self:start_timers()
	return true
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	for _, v in ipairs(self._clients) do
		v:close()
	end
	self._clients = {}
end

function app:on_output(app_src, sn, output, prop, value, timestamp)
	if sn ~= self._dev_sn then
		return nil, "Device Serial Number incorrect!"
	end

	for _, v in ipairs(self._tpl_outputs) do
		if v.name == output then
			-- TODO: write
		end
	end

	return nil, "Output not found!"
end

function app:on_input(app_src, sn, input, prop, value, timestamp, quality)
	if quality ~= 0 or prop ~= 'value' then
		return
	end

	local sys_id = self._sys:id()..'.'
	if string.find(sn, sys_id, 1, true) == 1 then
		sn = string.sub(sn, string.len(sys_id) + 1)
	end
	if string.len(sn) == 0 then
		return
	end

	local dev = self._devs[sn]
	if not dev then
		return
	end

	local inputs = dev[input]
	if not inputs then
		return
	end

	for _, v in ipairs(inputs) do
		self._station:set_tag_value(v.name, value, timestamp)
	end
end

function app:for_earch_client(func, ...)
	for _, v in ipairs(self._clients) do
		v[func](v, ...)
	end
end

function app:set_rdata_interval(interval)
	local interval = tonumber(interval)
	assert(interval, "RData Interval missing")
	if interval > 0 and (interval < 30 or interval > 3600) then
		return nil, "Incorrect interval number"
	end

	self._rdata_interval = interval
	if self._rdata_timer then
		self._rdata_timer:stop()
		self._rdata_timer = nil
	end

	if self._rdata_interval > 0 then
		self._rdata_timer = timer:new(function(now)
			self:for_earch_client('upload_rdata', now)
		end, self._rdata_interval)
		self._rdata_timer:start()
	end
end

function app:set_min_interval(interval)
	local interval = tonumber(interval)
	assert(interval, "Min Interval missing")
	if 60 % interval ~= 0 then 
		return nil, "Interval number incorrect"
	end

	self._min_interval = interval

	if self._min_timer then
		self._min_timer:stop()
		self._min_timer = nil
	end

	self._min_timer = timer:new(function(now)
		self:for_earch_client('upload_min_data', now)
	end, self._min_interval * 60, true)
	self._min_timer:start()
end

function app:start_timers()
	if self._rdata_interval > 0 then
		self._rdata_timer = timer:new(function(now)
			self:for_earch_client('upload_rdata', now)
		end, self._rdata_interval, true)
		self._rdata_timer:start()
	end

	self._min_timer = timer:new(function(now)
		self:for_earch_client('upload_min_data', now)
	end, self._min_interval * 60, true)
	self._min_timer:start()

	self._hour_timer = timer:new(function(now)
		self:for_earch_client('upload_hour_data', now)
	end, 3600, true)
	self._hour_timer:start()

	self._day_timer = timer:new(function(now)
		self:for_earch_client('upload_day_data', now)
	end, 3600 * 24, true)
	self._day_timer:start()
end

--- 返回应用对象
return app

