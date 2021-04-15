local ioe = require 'ioe'
local base = require 'app.base'
local tbl_equals = require 'utils.table.equals'
local pdu = require 'modbus.pdu.init'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'
local master = require 'modbus.master.skynet'

local app = base:subclass("HJ_AI_MODBUS_EX")
app.static.API_VER = 10

---
function app:on_init()
	local log = self:log_api()
	local conf = self:app_conf()

	self._pdu = pdu:new()
	self._data_pack = data_pack:new()
	self._data_unpack = data_unpack:new()

	if ioe.developer_mode() then
		conf.unit = 1
		conf.serial = conf.serial or {
			--port = "/tmp/ttyS3",
			port = "/dev/ttyUSB1",
			baudrate = 9600,
			data_bits = 8,
			parity = "NONE",
			stop_bits = 1,
			flow_control = "OFF"
		}
	end
end

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local conf = self:app_conf()
	local log = self:log_api()

	local sn = sys_id.."."..conf.dev_sn

	local meta = self._api:default_meta()
	meta.name = conf.dev_name or "AI Extension"

	conf.ai_list = conf.ai_list or {
		{ channel = 1, name = 'a34013', desc = '烟尘', unit = 'mg/m3', setting_prefix = 'Dust' },
		{ channel = 2, name = 'a01012', desc = '烟气温度', unit = 'C', setting_prefix = 'Temp' },
		{ channel = 3, name = 'a01013', desc = '烟气压力', unit = 'Pa', setting_prefix = 'Pressure' },
		{ channel = 6, name = 'a01011', desc = '烟气流速', unit = 'm/s', setting_prefix = 'Flow' },
		{ channel = 5, name = 'a01014', desc = '烟气湿度', unit = '%', setting_prefix = 'Humidity' },
	}

	local inputs = {}
	for _, v in pairs(conf.ai_list) do
		table.insert(inputs, {
			name = v.name,
			desc = v.desc,
			unit = v.unit
		})
		--[[
		table.insert(inputs, {
			name = v.name..'_low',
			desc = v.desc..' output low value',
			unit = v.unit
		})
		table.insert(inputs, {
			name = v.name..'_high',
			desc = v.desc..' output high value',
			unit = v.unit
		})
		--]]
	end

	self._dev = self._api:add_device(sn, meta, inputs)

	self._modbus = master:new('RTU', {link='serial', serial = conf.serial})

	--- 设定通讯口数据回调
	self._modbus:set_io_cb(function(io, unit, msg)
		self._dev:dump_comm(io, msg)
	end)

	return self._modbus:start()
end

--- 应用退出函数
function app:on_close(reason)
	if self._modbus then
		self._modbus:stop()
		self._modbus = nil
	end
	return true
end

--- 应用运行入口
function app:on_run(tms)
	local conf = self:app_conf()

	self:read_settings()

	self:read_ai(self._modbus, conf.unit, conf.ai_list)

	return conf.loop_gap or 1000
end

function app:read_settings()
	local log = self:log_api()
	local conf = self:app_conf()
	local station = conf.station or 'HJ212'

	if not self._settings then
		log:info("Wait for HJ212 Settings")
	end

	self._settings = ioe.env.wait('HJ212.SETTINGS', station)

	if self._settings.NO ~= self._last_sno then
		log:info("Got HJ212 Settings! Value:")
		log:info(cjson.encode(self._settings))
		self._last_sn = self._settings.NO
		-- TODO: Fire INFO
	end
end

function app:read_ai(modbus, unit, ai_list)
	local func = 0x03
	local addr = 0
	local dlen = 8
	local req, err = self._pdu:make_request(func, addr, dlen)
	if not req then
		return nil, err
	end
	local pdu, err = modbus:request(unit, req, 1000)
	if not pdu then
		return nil, err
	end

	local now = ioe.time()

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		self._log:warning("read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1)))
		return
	end

	local len = d:uint8(pdu, 2)
	assert(len >= dlen * 2, string.format("length issue :%d - %d", len, dlen * 2))

	local pdu_data = string.sub(pdu, 3)

	local settings = self._settings

	for _, v in ipairs(ai_list) do
		local index = assert(tonumber(v.channel)) - 1
		assert(index >= 0)
		local val, n_index = d:uint16(pdu_data, index * 2 + 1)
		local out_min = settings[v.setting_prefix..'_Min'] or 0
		local out_max = settings[v.setting_prefix..'_Max'] or 65535


		local mA = ((val - 0) * (20 - 4)) / (65535 - 0)
		mA = mA + 4

		local value = ((val - 0) * (out_max - out_min))/(65535 - 0)
		value = value + out_min
		--print(val, mA, value)

		self._dev:set_input_prop(v.name, "value", value, now, 0)
		self._dev:set_input_prop(v.name, 'RDATA', {
			value = value,
			value_src = mA,
			value_raw = val,
			timestamp = now,
		}, now, 0)
	end
end

--- 返回应用对象
return app
