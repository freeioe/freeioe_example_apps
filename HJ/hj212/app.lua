--- 导入需求的模块
local app_base = require 'app.base'
local client = require 'client_sc'
local csv_tpl = require 'csv_tpl'
local conf = require 'app.conf'

--- lua_HJ212_version: 2020-12-15

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_HJ212_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

--- 应用启动函数
function app:on_start()
	local sys = self._sys
	local conf = self._conf
	--[[
	conf.host = '127.0.0.1'
	conf.port = 16000
	]]--

	self._log:info("HJ212 Server: Host:"..conf.host..' Port:'..conf.port)

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

	--- 创建设备对象实例
	local sys_id = self._sys:id()
	local meta = self._api:default_meta()
	meta.name = 'HJ212' 
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'HJ212 Smart Device' 
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
		dev_sn = sys_id..'.'..meta.name
	end
	self._dev_sn = dev_sn

	self._dev = self._api:add_device(dev_sn, meta, inputs, inputs)
	self._dev_stat = self._dev:stat('port')

	self._tpl = tpl

	--- Start the connection
	self:start_connect_proc()

	return true
end

function app:start_connect_proc()
	if self._client then
		return
	end

	local conn_proc = nil
	local conn_timeout = 100
	conn_proc = function()
		self._client = client:new(self._conf)
		self._client:set_logger(self._log)
		local log = self._log

		self._client:set_dump(function(io, msg)
			--[[
			local basexx = require 'basexx'
			log:info(io, basexx.to_hex(msg))
			]]--
			log:debug(io, msg)
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

		local r, err = self._client:connect()
		if not r then
			self._log:error(tostring(err))
			self._client:close()
			self._client = nil
			if conn_timeout > 100 * 64 then
				conn_timeout = 100
			end
			self._sys:timeout(conn_proc, conn_timeout)
			conn_timeout = conn_timeout * 2
		end

		return r, err
	end

	self._sys:fork(conn_proc)
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	if self._client then
		self._client:close()
	end
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
--- 返回应用对象
return app

