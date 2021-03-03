--- 导入需求的模块
local class = require 'middleclass'
local event = require 'app.event'
local sysinfo = require 'utils.sysinfo'
local filebuffer = require 'buffer.file'
local client = require 'client_sc'
local types = require 'hj212.types'
local value_tpl = require 'value_tpl.parser'

local conn = class("FREEIOE_HJ212_APP_CONN")

--- 应用启动函数
function conn:initialize(app, conf, station, dev_sn_base)
	self._app = app
	self._sys = app._sys
	self._api = app._api
	self._conf = conf
	self._station = station
	self._dev_sn_base = dev_sn_base
	self._client = client:new(station, self._conf, self)
end

function conn:station()
	return self._station
end

function conn:client()
	return self._client
end

function conn:log(...)
	return self._client:log(...)
end

function conn:resend()
	return string.lower(self._conf.resend or '') == 'yes'
end

function conn:on_run()
	local timeout = self._client:timeout()
	local retry = self._client:retry()
	self._dev:set_input_prop('timeout', 'value', timeout)
	self._dev:set_input_prop('retry', 'value', retry)
	return true
end

function conn:start()
	---获取设备序列号和应用配置
	local sys_id = self._sys:id()
	local conf = self._conf

	local meta = self._api:default_meta()
	meta.name = 'HJ212 Connection - '..conf.name
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'HJ212 Connetion Status' 
	meta.series = 'N/A'

	local inputs = {
		{
			name = 'timeout',
			desc = 'Timeout time',
			vt = 'int',
			unit = 's'
		},
		{
			name = 'retry',
			desc = 'Retry count',
			vt = 'int',
		},
		{
			name = 'status',
			desc = 'Connection Status',
			vt = 'int'
		},
	}

	local dev_sn = conf.device_sn
	if dev_sn == nil or string.len(conf.device_sn) == 0 then
		dev_sn = self._dev_sn_base..'.'..conf.name
	end
	self._dev_sn = dev_sn

	self._dev = self._api:add_device(dev_sn, meta, inputs, inputs)
	self._dev_stat = self._dev:stat('port')

	if conf.value_tpl and conf.value_tpl ~= 'NONE' then
		value_tpl.init(self._sys:app_dir())
		self._value_tpl = value_tpl.load_tpl(conf.value_tpl, function(...) log:error(...) end)
	end

	if self:resend() then
		local cache_folder = sysinfo.data_dir().."/"..self._app:app_name()..'_CACHE_'..conf.name
		self:log('notice', 'Data cache folder:', cache_folder)
		self._fb = filebuffer:new(cache_folder, 128, 1024 * 8, 128)
		self._fb:start(function(pn, data)
			return self:data_request(pn, data, 'CACHE', true)
		end)
	end

	return self:start_connect()
end

function conn:start_connect()
	self._client:set_connection_cb(function(status)
		self._dev:set_input_prop('status', 'value', status)
		if not status then
			self._dev:fire_event(event.LEVEL_WARNING, event.EVENT_COMM, 'Server disconnected!', {})
		else
			self._dev:fire_event(event.LEVEL_INFO, event.EVENT_COMM, 'Connected to server!', {})
		end
	end)
	self._client:set_retry_cb(function(name, retry, max, data)
		local data = {
			name = name,
			retry = retry,
			max = max,
			data = data
		}
		self._dev:fire_event(event.LEVEL_WARNING, event.EVENT_COMM, 'Data send retry!', data)
	end)

	self._client:set_dump(function(io, msg)
		local dev = self._dev
		local dev_stat = self._dev_stat
		if dev then
			dev:dump_comm(io, msg)
			if not dev_stat then
				return
			end
			--- 计算统计信息
			if io == 'IN' then
				dev_stat:inc('bytes_in', string.len(msg))
			else
				dev_stat:inc('bytes_out', string.len(msg))
			end
		else
			self._sys:dump_comm(sys_id, io, msg)
		end
	end)

	return self._client:connect()
end

--- 应用退出函数
function conn:close(reason)
	self._client:close()
end

function conn:on_output(app_src, sn, output, prop, value, timestamp)
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

function conn:data_request(pn, data, key, from_fb)
	local r, request = pcall(require, 'hj212.request.'..pn)
	if not r then
		self:log('error', request)
		return true
	end

	local req = request:new(data, true)

	local r, err = self._client:request(req, function(resp, err)
		if not resp then
			return nil, "Upload "..key.." data failed. error:"..err
		end
		if resp:command() ~= types.COMMAND.DATA_ACK then
			return nil, "Upload "..key.." data failed. Unknown response:"..resp:command()
		end
		return true
	end)

	if not r then
		if from_fb then
			self:log('debug', 'Resend cache data failed', pn)
		elseif self._fb then
			self:log("info", 'Save unsend data to cache', pn)
			self._fb:push(pn, data)
		end
		self:log("error", "Upload "..key.." error:", err)
	else
		self:log("debug", "Upload "..key.." success")
	end
	return r, err
end

function conn:convert_version(data)
	local conf = self._conf
	if not conf.version or tonumber(conf.version) == 2017 then
		return data
	end
	assert(tonumber(conf.version) == 2005)

	local new_data = {}
	for _, v in ipairs(data) do
		local tag_name = v:tag_name()
		local tag = self._station:find_tag(tag_name)
		--print(tag_name, tag:hj2005_name())
		assert(tag)
		tag_name = tag:hj2005_name() or tag_name
		new_data[#new_data + 1] = v:clone(tag_name)
	end
	return new_data
end

function conn:convert_rate(data)
	if not self._value_tpl then
		return data
	end

	local new_data = {}
	for _, v in ipairs(data) do
		new_data[#new_data + 1] = v:transform(function(key, val)
			return self._value_tpl(v:tag_name(), key, val)
		end)
	end
	return new_data

end

function conn:convert_data(data)
	return self:convert_version(self:convert_rate(data))
end

function conn:upload_rdata(data)
	if not self._client:rdata_enable() then
		--- Client disabled the rdata
		return
	end

	data = self:convert_data(data)
	return self:data_request('rdata_start', data, 'RData')
end

function conn:upload_min_data(data)
	data = self:convert_data(data)
	return self:data_request('min_data', data, 'MIN')
end

function conn:upload_hour_data(data)
	data = self:convert_data(data)
	return self:data_request('hour_data', data, 'HOUR')
end

function conn:upload_day_data(data)
	data = self:convert_data(data)
	return self:data_request('day_data', data, 'DAY')
end

return conn

