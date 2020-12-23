--- 导入需求的模块
local class = require 'middleclass'
local client = require 'client_sc'
local conn = class("FREEIOE_HJ212_APP_CONN")

--- 应用启动函数
function conn:initialize(app, conf, station)
	self._app = app
	self._sys = app._sys
	self._api = app._api
	self._log = app._log
	self._conf = conf
	self._station = station
	self._client = client:new(station, self._conf)
end

function conn:station()
	return self._station
end

function conn:client()
	return self._client
end

function conn:start()
	---获取设备序列号和应用配置
	local sys_id = self._sys:id()
	local conf = self._conf

	local meta = self._api:default_meta()
	meta.name = 'Connection_'..conf.name
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'HJ212 Connetion Status' 
	meta.series = 'N/A'

	local inputs = {
		{
			name = 'timeout',
			desc = 'Timeout time',
			unit = 's'
		},
		{
			name = 'retry',
			desc = 'Retry count',
		},
	}

	local dev_sn = conf.device_sn
	if dev_sn == nil or string.len(conf.device_sn) == 0 then
		dev_sn = sys_id..'.HJ212_'..self._app:app_name()..'.'..conf.name
	end
	self._dev_sn = dev_sn

	self._dev = self._api:add_device(dev_sn, meta, inputs, inputs)
	self._dev_stat = self._dev:stat('port')

	return self:start_connect()
end

function conn:start_connect()
	local log = self._log

	self._client:set_logger(self._log)

	self._client:set_dump(function(io, msg)
		--[[
		local basexx = require 'basexx'
		log:info(io, basexx.to_hex(msg))
		]]--
		--log:debug(io, msg)
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
	self._log:warning('Connection closing', reason)
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

function conn:upload_rdata(data)
	local request = require 'hj212.request.rdata_start'
	local req = request:new(data, true)
	return self._client:request(req, function(resp, err)
		if not resp then
			self._log:error("Upload RData failed", err)
		end
	end)
end

function conn:upload_min_data(data)
	local request = require 'hj212.request.min_data'
	local req = request:new(data, true)
	return self._client:request(req, function(resp, err)
		if not resp then
			self._log:error("Upload RData failed", err)
		end
	end)
end

function conn:upload_hour_data(data)
	local request = require 'hj212.request.hour_data'
	local req = request:new(data, true)
	return self._client:request(req, function(resp, err)
		if not resp then
			self._log:error("Upload RData failed", err)
		end
	end)
end

function conn:upload_day_data(data)
	local request = require 'hj212.request.day_data'
	local req = request:new(data, true)
	return self._client:request(req, function(resp, err)
		if not resp then
			self._log:error("Upload RData failed", err)
		end
	end)
end

return conn

