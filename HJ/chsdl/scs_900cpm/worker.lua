local class = require 'middleclass'
local cjson = require 'cjson.safe'
local pdu = require 'modbus.pdu.init'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'
local bcd = require 'bcd'
local ioe = require 'ioe'
local retry = require 'utils.retry'

local worker = class("SCS-900CPM.worker")

local SF = string.format

--[[
HJ212-RS:
0-关闭 1-运行 2-校准 3-维护 4-报警 5-反吹

HJ212 Flag:
N-正常 F-停运 M-维护 S-手工输入 D-故障 C-校准 T-超限 B-通讯异常

i12001 / i12007:
0=运行  1=维护  2=故障  3=校准（校标，校零)  5=反吹 6=标定

i12003 / i12009:
0=正常  1=气路堵塞  2=上限报警  3=下限报警  4=缺仪表风  5=温控报警  6=光强弱报警  7=伴热管温度报警  8=氧传感器老化报警 9=探头温度故障
]]--

--[[
--
0x0001 运行
0x0010 反吹
0x0020 标定
0x0040 维护
0x0080 故障
--]]
-- Returns RS, i12001, i12003, flag
local function map_state(state)
	local rs = 1
	local flag = 'N'
	local i12001 = 0
	local i12003 = 0
	if state & 0x0001 ~= 0 then
		--- initialized
	end
	if state & 0x0010 ~= 0 then
		rs = 5
		flag = 'M' -- TODO:
		i12001 = 5
		i12003 = 0
	end
	if state & 0x0020 ~= 0 then
		rs = 2
		flag = 'C'
		i12001 = 6
		i12003 = 0
	end
	if state & 0x0040 ~= 0 then
		rs = 3
		flag = 'M'
		i12001 = 1
		i12003 = 0
	end
	if state & 0x0080 ~= 0 then
		rs = 4
		flag = 'D'
		i12001 = 2
		i12003 = 99 --TODO:
	end

	return rs, i12001, i12003, flag
end


function worker:initialize(app, unit, dev, conf)
	self._log = app:log_api()
	self._unit = unit
	self._dev = dev
	self._conf = conf
	self._pdu = pdu:new()
	self._data_pack = data_pack:new()
	self._data_unpack = data_unpack:new()
	self._eq_buf = {}
end

function worker:run(modbus, plc_modbus)
	local r, err = self:read_summary(modbus)
	if not r then
		self:invalid_dev()
	end
end

function worker:invalid_dev()
	local quality = -1
	local flag = 'B'

	local now = ioe.time()

	self._dev:set_input_prop('RS', "value", 0, now, quality)

	self._dev:set_input_prop('state', "value", -1, now, quality)

	self:set_input('a34013', 0, nil, now, quality, flag)
end

local function map_info_without_raw(info)
	local ret = {}
	for k, v in pairs(info) do
		if k ~= i13011 then
			ret[k] == v
		end
	end
	return ret
end


function worker:set_input(name, value, info, now, quality, flag)	
	if info then
		local rinfo = map_info_without_raw(info)
		self._dev:set_input_prop(name, 'INFO', rinfo, now, quality)
	end

	local rdata = {
		value = value,
		value_src = info and info.i13011 or nil,
		timestamp = now,
		flag = flag
	}
	self._dev:set_input_prop(name, 'value', value, now, quality)
	self._dev:set_input_prop(name, 'RDATA', cjson.encode(rdata), now, quality)
	for k, v in pairs(info) do
		self._dev:set_input_prop(name .. '-' .. k, 'value', v, now, quality)
	end
end

function worker:read_summary(modbus)
	local func = 0x03
	local start_addr = 0
	local dlen = 15

	local req, err = self._pdu:make_request(func, start_addr, dlen)
	if not req then
		return nil, err
	end

	--- Retry request in three times
	local pdu, err = retry(3, modbus.request, modbus, self._unit, req, 1000)
	if not pdu then
		return nil, err
	end

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		local err = "read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1))
		self._log:warning(err)
		return nil, err
	end

	local len = d:uint8(pdu, 2)
	assert(len >= dlen * 2, SF("length issue :%d - %d", len, dlen * 2))

	local pdu_data = string.sub(pdu, 3)
	local now = ioe.time()

	local a34013 = d:float(pdu_data, 1)

	local i13013_a = d:float(pdu_data, 5)
	local i13013_b = d:float(pdu_data, 9)
	local i13006 = d:float(pdu_data, 13)
	local i13002 = d:float(pdu_data, 17)
	local i13013 = d:float(pdu_data, 21)
	local i13011 = d:float(pdu_data, 25)

	local state = d:float(pdu_data, 29)

	local rs, i12001, i12003, flag = map_state(state)

	local info = {
		i12001 = i12001,
		i12002 = i12003 == 0 and 0 or 1,
		i12003 = i12003,
		--i13013_a = i13013_a,
		--i13013_b = i13013_b,
		i13013 = i13013,
		i13006 = i13006,
		i13002 = i13002,
		i13011 = i13011
	}

	self._dev:set_input_prop('RS', "value", rs, now)
	self._dev:set_input_prop('state', "value", state, now)

	self:set_input('a34013', a34013, info, now, 0, flag)
end

return worker
