local class = require 'middleclass'
--- 导入需要的模块
local ubus = require 'ubus'
local focas = require 'focas'
local cjson = require 'cjson'

local app = class("Wuling.Fanuc")
app.static.API_VER = 10

--- 应用启动函数
function app:start()
	---获取设备序列号和应用配置
	local sys_id = self._sys:id()

	local config = self._conf or {}
	config.devs = config.devs or {
		{ ip="192.168.0.200", port=8193, name = 'cnc01', sn = 'xxx-xx-1', tpl = 'cnc' },
		--{ ip="127.0.0.2", port=8193, name = 'cnc02', sn = 'xxx-xx-2', tpl = 'cnc' },
	}
	--print(cjson.encode(config.devs))

	local bus = ubus:new()
	bus:connect()

	local r, err = bus:status()
	if not r then
		self._log:error("Connect to UBUS failed!", err)
		return false
	end
	self._ubus = bus
	self._ubus_name = 'focas'

	self._devs = {}
	for _, v in ipairs(helper:devices()) do
		assert(v.sn and v.name and v.ip and v.port and v.tpl)

		--- 生成设备的序列号
		local dev_sn = sys_id.."."..v.sn
		local tpl, err = csv_tpl.load_tpl(v.tpl)
		--print(cjson.encode(tpl))
		if not tpl then
			self._log:error("loading csv tpl failed", err)
		else
			local meta = self._api:default_meta()
			meta.name = tpl.meta.name or "Fanuc CNC"
			meta.description = tpl.meta.desc or "Fanuc CND Device"
			meta.series = tpl.meta.series or "XXX"
			meta.inst = v.name
			--- inputs
			local inputs = {}
			for _, v in ipairs(tpl.inputs) do
				inputs[#inputs + 1] = {
					name = v.name,
					desc = v.desc,
					vt = v.vt
				}
			end

			local focas_dev = focas:new(v.ip, v.port, v.name, v.sn, tpl)
			--- Funcs
			for _, v in ipairs(tpl.funcs) do
				v.inputs = focas_dev:inputs(v.func, v.name, v.desc, v.vt, v.rate)
				for _, v in ipairs(v.inputs) do
					inputs[#inputs + 1] = {
						name = v.name,
						desc = v.desc,
						vt = v.vt
					}
				end
			end

			local dev = self._api:add_device(dev_sn, meta, inputs, outputs)

			table.insert(self._devs, {
				sn = dev_sn,
				dev = dev,
				focas = focas_dev,
				tpl = tpl,
			})
		end
	end

	for _, dev in ipairs(self._devs) do
		local r, err = dev.focas:connect(self._ubus, self._ubus_name)
		if not r then
			self._log:error("Connect to device failed!", err)
		end
	end

	return true
end

--- 应用退出函数
function app:close(reason)
	self._log:notice("app closed", self._name, reason)
end

function app:read_packet(dev, focas, func, params, inputs)
	--- 设定读取的起始地址和读取的长度
	local func = focas:get_func_name(func or 'read_pmc')
	if func == 'read_pmc' then
		return
	end

	local f = focas[func]
	if not f then
		self._log:error("function code incorrect", func)
		return nil, "function code incorrect"
	end

	local data, err = f(focas, table.unpack(params))
	if not data then
		self._log:error('call '..func..' failed', err)
		return nil, err
	end

	--local cjson = require 'cjson.safe'
	--print(cjson.encode(data))

	if func ~= 'read_pmc' and #inputs == 1 then
		new_data = {}
		local input = inputs[1]
		if type(data) == 'table' then
			if #data >= 1 then
				new_data[input.vname] = data[1]
			end
		else
			new_data[input.vname] = data
		end

		data = new_data
	end

	for i, input in ipairs(inputs) do
		local key = input.vname or i
		print(data[key], key, input.vt,  input.rate)

		if input.rate and input.rate ~= 1 then
			local val = (data[key] or 0) * input.rate
			dev:set_input_prop(input.name, "value", val)
		else
			if input.vt == 'int' then
				dev:set_input_prop(input.name, "value", math.tointeger(data[key]))
			else
				dev:set_input_prop(input.name, "value", data[key])
			end
		end
	end

	return true
end

function app:invalid_dev(dev, pack)
	for _, input in ipairs(pack.inputs) do
		dev:set_input_prop(input.name, "value", 0, nil, 1)
	end
end

function app:read_dev(dev, focas)
	local r, err = self:read_current(dev, focas)
	if not r then
		self:invalid_dev(dev)
	end
end

--- 应用运行入口
function app:run(tms)
	for _, dev in ipairs(self._devs) do
		self:read_dev(dev.dev, dev.focas)
	end

	--- 返回下一次调用run之前的时间间隔
	return self._conf.loop_gap or 5000
end

--- 返回应用对象
return app
