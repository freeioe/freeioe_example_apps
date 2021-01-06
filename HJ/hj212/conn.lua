--- 导入需求的模块
local class = require 'middleclass'
local client = require 'client_sc'
local types = require 'hj212.types'

local conn = class("FREEIOE_HJ212_APP_CONN")

--- 应用启动函数
function conn:initialize(app, conf, station, dev_sn_base)
	self._app = app
	self._sys = app._sys
	self._api = app._api
	self._conf = conf
	self._station = station
	self._dev_sn_base = dev_sn_base
	self._client = client:new(station, self._conf)
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

	return self:start_connect()
end

function conn:start_connect()
	self._client:set_connection_cb(function(status)
		self._dev:set_input_prop('status', 'value', status)
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

function conn:data_request(req, key)
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
		self:log("error", err)
	else
		self:log("debug", "Upload "..key.." success")
	end
	return r, err
end

function conn:upload_rdata(data)
	local request = require 'hj212.request.rdata_start'
	local req = request:new(data, true)
	return self:data_request(req, 'RData')
end

function conn:upload_min_data(data)
	local request = require 'hj212.request.min_data'
	local req = request:new(data, true)
	return self:data_request(req, 'MIN')
end

function conn:upload_hour_data(data)
	local request = require 'hj212.request.hour_data'
	local req = request:new(data, true)
	return self:data_request(req, 'HOUR')
end

function conn:upload_day_data(data)
	local request = require 'hj212.request.day_data'
	local req = request:new(data, true)
	return self:data_request(req, 'DAY')
end

return conn

