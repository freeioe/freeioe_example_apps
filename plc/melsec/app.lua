--- 导入需求的模块
local app_base = require 'app.base'
local client = require 'client_sc'
local csv_tpl = require 'csv_tpl'
local packet_split = require 'packet_split'
local data_paser = require 'melsec.data.parser'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_PLC_AB_PLCTAG_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

--- 应用启动函数
function app:on_start()
	local sys = self._sys
	local conf = self._conf
	--[[
	conf.host = '192.168.250.1'
	conf.port = 0xAF12
	]]--

	self._log:info("Ethernet IP/CIP: Host:"..conf.host..' Route:'..conf.route)

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
	meta.name = 'PLC' 
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'PLC via ENIP/CIP' 
	meta.series = 'N/A'

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
				vt = v.vt,
				unit = v.unit,
			}
			tpl_outputs[#tpl_outputs + 1] = v
		end
	end

	local dev_sn = conf.device_sn
	if dev_sn == nil or string.len(conf.device_sn) == 0 then
		dev_sn = sys_id..'.'..meta.name
	end
	self._dev_sn = dev_sn

	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs)

	--- Split the inputs into packets
	local split = packet_split:new()
	local packets = split:split(tpl.props)

	self._tpl = tpl
	self._tpl_inputs = tpl_inputs
	self._tpl_outputs = tpl_outputs
	self._packets = packets

	--- Start the connection
	self:start_connect_proc()

	return true
end

function app:start_connect_proc()
	if self._client then
		return
	end

	local conn_proc = nil
	conn_proc = function()
		local conf = self._conf
		local network = conf.network or 0
		local index = conf.index or 0xFF
		local io = conf.io or 0x03FF
		local station = conf.station or 0
		self._client = client:new(conf.host, '4E_BIN', network, index, io, station)
		self._client:set_comm_cb(function(dir, data)
			--[[
			local basexx = require 'basexx'
			print(dir, basexx.to_hex(data))
			]]--
			if self._dev then
				self._dev:dump_comm(dir, data)
			end
		end)

		local r, err = self._client:connect()
		if not r then
			self._log:error(tostring(err))
			self._client:close()
			self._client = nil
			self._sys:fork(conn_proc)
		end

		return r, err

	end
	self._sys:fork(conn_proc)
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	self._closing = {}
	self._sys:sleep(5000, self._closing)
	self._client:close()
end

function app:read_pack(pack)
	local parser = data_paser:new(false)

	local inputs = pack.inputs
	local tags = {}
	for _, v in ipairs(inputs) do
		tags[#tags + 1] = {
			input = v,
			set_value = function(value, quality)
				self._dev:set_input_prop(v.name, 'value', value, nil, quality)
			end,
			unpack = function(raw)
				assert((v.index - pack.start) % 8 == 0, 'Index error!!')
				local index = (v.index - pack.start) // 8
				return parser(v.dt, raw, index + 1, v.slen)
			end
		}
	end
	self._log:trace('READ_PACK', pack.read_type, pack.sc_name, pack.start, pack.len)

	local read_func = self._client.read_sc
	if pack.read_type then
		if pack.read_type == 'WORD' then
			read_func = self._client.read_words
		else
			read_func = self._client.read_bits
		end
	else
		--self._log:trace("Auto dectect command by sc name")
	end
	local r, err = read_func(self._client, pack.sc_name, pack.start, pack.len, function(val, err)
		if not val then
			self._log:error('Read PLC tags error:', err)
			return nil, err
		else
			self._log:debug('Value from PLC', val, err)
		end

		for _, v in ipairs(tags) do
			local val, err = v.unpack(val)
			--print(v.input.name, val, err)
			if val then
				v.set_value(val, 0)
			else
				v.set_value(0, -1)
			end
		end
		--print(dp('uint16', val))
	end)

	return r, err
end

function app:write_output(input, val)
	local sc = {
		sc_name = input.sc_name,
		index = input.index,
		values = {}
	}

	table.insert(sc.values, {
		fmt = input.dt,
		val = val
	})

	local write_func = self._client.read_sc
	if input.read_type then
		if input.read_type == 'WORD' then
			write_func = self._client.write_words
		else
			write_func = self._client.write_bits
		end
	else
		--self._log:trace("Auto dectect command by sc name")
	end

	local r, err = write_func(self._client, sc, function(resp, err)
		return resp, err
	end)
	if not r then
		self._log:error("Write output failed", err)
	end

	return r, err
end

function app:on_run(tms)
	local begin_time = self._sys:time()

	--[[
	local r, err = self._client:read_words('R*', 10400, 480, function(val, err)
		if not val then
			self._log:error('Read PLC tag error:', err)
		else
			self._log:debug('Value from PLC', val, err)
		end
		local data_paser = require 'melsec.data.parser'
		local dp = data_paser:new(false)

		print(dp('uint16', val))
	end)
	]]--

	--[[
	local r, err = self._client:write_tag('tag1', 'UINT', 111, function(val, err)
		if not val then
			self._log:error('Wirte PLC tag error:', err)
		else
			self._log:debug('Value from PLC', val, err)
		end
	end)
	]]--


	for _, v in ipairs(self._packets) do
		self._sys:sleep(0)
		if self._closing then
			return --- Return
		end
		self:read_pack(v)
	end

	if self._closing then
		self._sys:wakeup(self._closing)
		self._log:debug("Closing...")
		return 10000 --- end this loop
	end


	local next_tms = (self._conf.loop_gap or 1000) - ((self._sys:time() - begin_time) * 1000)
	return next_tms > 0 and next_tms or 0
end

function app:on_output(app_src, sn, output, prop, value, timestamp)
	if sn ~= self._dev_sn then
		return nil, "Device Serial Number incorrect!"
	end

	for _, v in ipairs(self._tpl_outputs) do
		if v.name == output then
			return self:write_output(v, value)
		end
	end


	return nil, "Output not found!"
end
--- 返回应用对象
return app

