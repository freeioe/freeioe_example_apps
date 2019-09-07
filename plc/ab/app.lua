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

--- 应用启动函数
function app:on_start()
	local sys = self._sys
	local conf = self._conf

	local protocol = conf.protocol or 'ab_eip'  -- ab-eip ab_eip
	local host = conf.host or '10.206.1.27' -- 'ip'
	local path = conf.path or '1,0'
	local cpu = string.lower(conf.cpu or 'LGX')
	--[[ 
		AB_PLC: plc5, plc, slc, slc500
		AB_LGX_PCCC: lgxpccc, logixpccc, lgxplc5, logixplc5, lgx-pccc, logix-pccc, lgx-plc5, logix-plc5
		AB_MLGX800: micrologix800, mlgx800, micro800
		AB_MLGX: mricrologix, mlgx
		AB_LGX: compactlogix, clgx, lgx, controllogix, contrologix, flexlogix, flgx
	]]--

	local function get_path_base(prop_path)
		local path_base = string.format('protocol=%s&gateway=%s&path=%s&cpu=%s', protocol, host, prop_path or path, cpu)
		local port = tonumber(conf.port)
		if port then
			path_base = path_base..'&gateway_port='..math.floor(port)
		end
		return path_base
	end

	local tpl_id = conf.tpl
	local tpl_ver = conf.ver
	local tpl_file = 'example'

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
			tpl_inputs[#tpl_inputs] = v
		end
		if string.find(v.rw, '[Ww]') then
			outputs[#outputs + 1] = {
				name = v.name,
				desc = v.desc,
				vt = v.vt,
				unit = v.unit,
			}
			tpl_outputs[#tpl_outputs] = v
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
		local path_base = get_path_base(v.path)
		local tag_path = string.format('&elem_size=%d&elem_count=%d&name=%s', v.elem_size, v.elem_count, v.elem_name)
		v.tag = plctag.create(path_base .. path, self._conf.timeout or 5000)
	end
	
	self._tpl = tpl
	self._tpl_inputs = inputs
	self._tpl_outputs = outputs
	self._packets = packets

	return true
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	for _, v in ipairs(self._packets) do
		if v.tag then
			plctag.destroy(v.tag)
			v.tag = nil
		end
	end
end

--- 应用运行入口
function app:on_run(tms)
	local begin_time = self._sys:time()

	local dev = self._dev

	self._log:debug('Start', os.date())

	local function read_tag(pack)
		local tag = pack.tag
		local status = plctag.status(tag)
		if status == plctag.Status.OK then
			local rc = plctag.read(tag, self._conf.timeout or 5000)
			if rc == plctag.Status.OK then
				for _, input in ipairs(pack.inputs) do
					local f = assert(plctag['get_'..input.dt], "Not supported read function")
					local val = f(tag, input.offset)

					print(input.name, val)

					if input.rate and input.rate ~= 1 then
						val = val * input.rate
					end
					dev:set_input_prop(input.name, "value", val)
				end
			else
				self._log:error("Read PLC Error", plctag.decode_error(rc))
			end
		end
	end

	for _, v in ipairs(self._packets) do
		if v.tag then
			read_tag(v)
		end
	end

	self._log:debug('End', os.date())

	local next_tms = (self._conf.loop_gap or 1000) - ((self._sys:time() - begin_time) * 1000)
	return next_tms > 0 and next_tms or 0
end

function app:on_output(app_src, sn, output, prop, value, timestamp)
	if sn ~= self._dev_sn then
		return nil, "Device Serial Number incorrect!"
	end

	for _, v in ipairs(self._tpl_outputs) do
		if v.name == output then
			local tag = nil  ---TODO: How to write one single value if offset is not zero

			local f = plctag['set_'..v.dt]
			if not f then
				return nil, "Data type not supported"
			end

			f(tag, v.offset * v.elem_size, tonumber(value))

			local rc = plctag.write(tag, self._conf.timeout or 5000)
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

