--- 导入需求的模块
local app_base = require 'app.base'
local csv_tpl = require 'csv_tpl'
local plctag = require 'plctag'
local packet_split = require 'packet_split'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_PLC_AB_PLCTAG_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

function app:connected()
	return self._client ~= nil and self._client:connected()
end

function app:get_tag_path(elem_size, elem_count, elem_name)
	local conf = self._conf

	local protocol = conf.protocol or 'ab_eip'  -- ab-eip ab_eip
	local host = conf.host or '127.0.0.1' --'10.206.1.27' -- 'ip'
	local path = conf.path or '1,0'
	local cpu = string.lower(conf.cpu or 'LGX')
	--[[
		AB_PLC: plc5, plc, slc, slc500
		AB_LGX_PCCC: lgxpccc, logixpccc, lgxplc5, logixplc5, lgx-pccc, logix-pccc, lgx-plc5, logix-plc5
		AB_MLGX800: micrologix800, mlgx800, micro800
		AB_MLGX: mricrologix, mlgx
		AB_LGX: compactlogix, clgx, lgx, controllogix, contrologix, flexlogix, flgx
	]]--

	local path_base = string.format('protocol=%s&gateway=%s&path=%s&cpu=%s', protocol, host, path, cpu)
	local port = tonumber(conf.port)
	if port then
		path_base = path_base..'&gateway_port='..math.floor(port)
	end
	local elem_path = string.format('&elem_size=%d&elem_count=%d&name=%s', elem_size, elem_count, elem_name)

	return path_base .. elem_path
end

--- 应用启动函数
function app:on_start()
	local sys = self._sys
	local conf = self._conf

	self._log:info("AB PLC Host", conf.host, conf.port)

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

	-- 加载模板
	csv_tpl.init(self._sys:app_dir())
	local tpl = csv_tpl.load_tpl(tpl_file, function(...) self._log:error(...) end)

	--- 创建设备对象实例
	local sys_id = self._sys:id()
	local meta = self._api:default_meta()
	meta.name = tpl.meta.name
	meta.manufacturer = tpl.meta.manufacturer or "Allen-Bradley"
	meta.description = tpl.meta.desc
	meta.series = tpl.meta.series

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

	local split = packet_split:new()
	local packets = split:split(tpl.props)
	for _, v in ipairs(packets) do
		--print(v.elem_size, v.elem_count, v.elem_name)
		local tag_path = self:get_tag_path(v.elem_size, v.elem_count, v.elem_name)
		v.tag = plctag.create(tag_path, self._conf.timeout or 5000)
		v.tag_path = tag_path
		if v.tag < 0 then
			self._log:error("Failed to open tag, path", tag_path)
			self.tag = nil
		end
		self._sys:sleep(0)
	end

	self._tpl = tpl
	self._tpl_inputs = tpl_inputs
	self._tpl_outputs = tpl_outputs
	self._packets = packets

	return true
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	self._closing = {}
	self._sys:sleep(5000, self._closing)
	for _, v in ipairs(self._packets) do
		if v.tag then
			plctag.destroy(v.tag)
			v.tag = nil
		end
		self._sys:sleep(0)
	end
end

function app:block_read(dev)
	local function read_tag(pack)
		local tag = pack.tag
		local rc = plctag.read(tag, self._conf.timeout or 2000)
		if rc == plctag.Status.OK then
			self._log:debug("Readed tag path", pack.tag_path)
			for _, input in ipairs(pack.props) do
				local f = assert(plctag['get_'..input.dt], "Not supported read function:"..input.dt)
				local val = f(tag, input.offset * pack.elem_size)

				--print(input.name, val)
				if input.dt == 'bool' then
					val = val and 1 or 0
				end

				if input.rate and input.rate ~= 1 then
					val = val * input.rate
				end
				dev:set_input_prop(input.name, "value", val)
			end
		else
			self._log:error("Read PLC Error", plctag.decode_error(rc), pack.tag_path)
		end
	end

	for _, v in ipairs(self._packets) do
		self._sys:sleep(0)

		if self._closing then
			break
		end

		if v.tag then
			read_tag(v)
		else
			self._log:debug("Tag missing!!!")
		end
	end
end

function app:async_read(dev)
	local function parse_tag(pack)
		local tag = pack.tag
		for _, input in ipairs(pack.props) do
			local f = assert(plctag['get_'..input.dt], "Not supported read function:"..input.dt)
			local val = f(tag, input.offset * pack.elem_size)

			--print(input.name, val)
			if input.dt == 'bool' then
				val = val and 1 or 0
			end

			if input.rate and input.rate ~= 1 then
				val = val * input.rate
			end
			dev:set_input_prop(input.name, "value", val)
		end
	end

	local packs = {}
	for _, v in ipairs(self._packets) do
		self._sys:sleep(0)
		if self._closing then
			return --- Return
		end
		--
		if v.tag then
			local rc = plctag.read(v.tag, 0)
			if rc ~= plctag.Status.OK and rc ~= plctag.Status.PENDING then
				self._log:error("Async Read Pre Error", plctag.decode_error(rc), v.tag_path)
			else
				packs[#packs + 1] = v
			end
		end
	end
	local be_time = self._sys:time()
	while #packs > 1 do
		self._sys:sleep(20)
		if self._closing then
			return --- Return
		end
		if (self._sys:time() - be_time) > (self._conf.timeout or 2000) then
			self._log:error("Async Read Timeout!!!")
			return --- Return
		end

		for i, v in ipairs(packs) do
			local rc = plctag.read(v.tag, 0)
			if rc ~= plctag.Status.PENDING then
				if rc == plctag.Status.OK then
					parse_tag(v)
				else
					self._log:error("Async Read Data Error", plctag.decode_error(rc), v.tag_path)
				end
				table.remove(packs, i)
			end
		end
	end
end

--- 应用运行入口
function app:on_run(tms)
	local begin_time = self._sys:time()

	local dev = self._dev

	--self._log:debug('Start', os.date())

	if self._conf.block_read then
		self:block_read(dev)
	else
		self:async_read(dev)
	end

	if self._closing then
		self._sys:wakeup(self._closing)
		self._log:debug("Closing...")
		return 10000 --- end this loop
	end

	--self._log:debug('End', os.date())

	local next_tms = (self._conf.loop_gap or 1000) - ((self._sys:time() - begin_time) * 1000)
	return next_tms > 0 and next_tms or 0
end

function app:on_output(app_src, sn, output, prop, value, timestamp)
	if sn ~= self._dev_sn then
		return nil, "Device Serial Number incorrect!"
	end

	for _, v in ipairs(self._tpl_outputs) do
		if v.name == output then
			local split = packet_split:new()
			local elem_size = split:elem_size(v)
			local tag_path = self:get_tag_path(elem_size, v.offset + 1, v.elem_name)
			self._log:info('Write tag', tag_path, value, type(value))
			local tag = plctag.create(tag_path, self._conf.timeout or 5000)
			if tag < 0 then
				return nil, "Failed to find tag"
			end
			local rc = plctag.read(tag, self._conf.timeout or 5000)
			if not rc then
				return nil, "failed to read tag before write"
			end

			local f = plctag['set_'..v.dt]
			if not f then
				return nil, "Data type not supported"
			end

			if v.dt == 'bool' then
				value = tonumber(value) == 1 or value == true or false
			elseif v.dt == 'string' then
				value = tostring(value)
			else
				value = tonumber(value)
			end

			--print(output, value)
			f(tag, v.offset * elem_size, value)

			rc = plctag.write(tag, self._conf.timeout or 5000)
			if rc ~= plctag.Status.OK then
				return nil, plctag.decode_error(rc)
			end

			return true, "Write value done!"
		end
	end

	return nil, "Output not found!"
end

--- 返回应用对象
return app

