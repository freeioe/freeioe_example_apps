local class = require 'middleclass'
local pdu = require 'modbus.pdu.init'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'
local date = require 'date'
local ioe = require 'ioe'
local bcd = require 'bcd'
local retry = require 'utils.retry'

local worker = class("CODcr_1001.worker")

local SF = string.format

--[[
1 离线  处于离线模式，不执行远程控制命令
2 待机
3 测量
4 维护
5 清洗
6 故障
7 标液一校准  低点校准
8 标液二校准  高点校准
9 预留
10 标定
11 标样核查
12~99 可扩展
]]--
--[[
i12101:
0=空闲  1=做样  2=清洗  3=维护  4=故障 5=校准 6=标样核查
--]]
--[[
HJ212-RS 0-关闭 1-运行 2-校准 3-维护 4-报警 5-反吹
]]--
local function convert_status(status)
	if status == 1 or status == 2 then
		return 0, 1
	elseif status == 3 then
		return 1, 1
	elseif status == 4 then
		return 3, 3
	elseif status == 5 then
		return 5, 1
	elseif status == 6 then
		return 4, 4
	elseif status == 7 or status == 8 then
		return 5, 2
	elseif status == 9 then
		return 0, 1
	elseif status == 10 then
		return 5, 2
	elseif status == 11 then
		return 6, 2
	end
	return 4, 0
end

--[[
HJ212 Flag:
N-正常
F-停运
M-维护
S-手工输入
D-故障
C-校准
T-超限
B-通讯异常
]]--
local function convert_flag(flag, flag_o)
	if flag_o == 'c' then
		if flag == 'z' or flag == 's' then
			return 'C'
		end
		return 'C'
	else
		return flag
	end
end

--[[
0 - 缺试剂告警
1 - 缺水样告警
2 - 缺空白水告警
3 - 缺标液
4 - 备用
5 - 标定异常告警
6 - 超量程告警
7 - 加热异常
8 - 低试剂预警
9 - 超上限告警
10 - 超下限告警
11 - 仪表内部其它异常
12 - 备用
13 - 备用
14 - 备用
]]--
--[[
i12103:
0=正常  1=缺试剂  2=缺蒸馏水  3=缺标液  4=缺水样  5=加热故障  6=光源异常  7=测量超上限  8=测量超下限 9=排残液故障  10=采样故障
]]--

local function convert_alarm(alarm1, alarm2)
	--print(alarm1, alarm2, 1 << 15, alarm1 & (1 << 15))
	if alarm1 & (1 << (16 - 1)) ~= 0 then
		return 1
	elseif alarm1 & (1 << (16 - 2)) ~= 0 then
		return 4
	elseif alarm1 & (1 << (16 - 3)) ~= 0 then
		return 2
	elseif alarm1 & (1 << (16 - 4)) ~= 0 then
		return 3
	elseif alarm1 & (1 << (16 - 6)) ~= 0 then
		return 10 -- TODO:
	elseif alarm1 & (1 << (16 - 7)) ~= 0 then
		return 7
	elseif alarm1 & (1 << (16 - 8)) ~= 0 then
		return 5
	elseif alarm1 & (1 << (16 - 8)) ~= 0 then
		return 0
	elseif alarm1 & (1 << (16 - 10)) ~= 0 then
		return 7
	elseif alarm1 & (1 << (16 - 11)) ~= 0 then
		return 8
	elseif alarm1 & (1 << (16 - 12)) ~= 0 then
		return 10
	end

	return 0
end

local function bcd_num(pdu_data, index)
	return bcd.decode(string.sub(pdu_data, index, index))
end

local function convert_datetime(pdu_data, index)
	local year = bcd_num(pdu_data, index)
	local mon = bcd_num(pdu_data, index + 1)
	local day = bcd_num(pdu_data, index + 2)
	local hour = bcd_num(pdu_data, index + 3)
	local min = bcd_num(pdu_data, index + 4)
	local sec = bcd_num(pdu_data, index + 5)

	local t = os.time({
		year = 2000 + year,
		month = mon,
		day = day,
		hour = hour,
		min = min,
		sec = sec
	})
	--print(os.date('%FT%T', t))

	return t
end

function worker:initialize(app, unit, dev, conf)
	self._log = app:log_api()
	self._unit = unit
	self._dev = dev
	self._conf = conf
	self._pdu = pdu:new()
	self._data_pack = data_pack:new()
	self._data_unpack = data_unpack:new()

	self._value = {
		value = 0,
		value_src = 0,
		timestamp = ioe.time(),
		flag = 'B'
	}
end

function worker:run(modbus)
	local r, err = self:read_val(modbus)
	if not r then
		self:invalid_dev()
		return nil, err
	end

	self:read_state(modbus)

	return true
end

function worker:invalid_dev()
	local now = ioe.time()

	self._dev:set_input_prop('status', 'value', -1, now, -1)
	self._dev:set_input_prop('alarm', 'value', -1, now, -1)
	self._dev:set_input_prop('RS', 'value', 0, now, -1)

	self._dev:set_input_prop('w21003', 'value', 0, now, -1)
	self._dev:set_input_prop('w21003_raw', 'value', 0, now, -1)
	self._dev:set_input_prop('w21003', 'RDATA', {
		value = 0,
		value_src = 0,
		flag = 'B',
		timestamp = now
	}, now, -1)
end

function worker:read_raw(modbus)
	local func = 0x03
	local addr = 0x22C0
	local dlen = 4
	local req, err = self._pdu:make_request(func, addr, dlen)
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
		self._log:warning("read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1)))
		return nil, 'Modbus error'..d:uint8(pdu, 1)
	end

	local len = d:uint8(pdu, 2)
	assert(len >= dlen * 2, SF("length issue :%d - %d", len, dlen * 2))

	local pdu_data = string.sub(pdu, 3)

	return d:float(pdu_data, 5)
end

function worker:read_val(modbus)
	local func = 0x03
	local addr = 0x1000
	local dlen = 9
	local req, err = self._pdu:make_request(func, addr, dlen)
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
		self._log:warning("read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1)))
		return nil, 'Modbus error'..d:uint8(pdu, 1)
	end

	local len = d:uint8(pdu, 2)
	assert(len >= dlen * 2, SF("length issue :%d - %d", len, dlen * 2))

	local pdu_data = string.sub(pdu, 3)

	local dtime = convert_datetime(pdu_data, 1)
	local val = d:float(pdu_data, 11)
	local flag_o = string.sub(pdu_data, 17, 17)
	local flag = string.sub(pdu_data, 18, 18)

	local raw, err = self:read_raw(modbus)
	if not raw then
		return nil, err
	end

	local now = ioe.time()

	self._dev:set_input_prop('w21003', 'value', val, now)
	self._dev:set_input_prop('w21003_raw', 'value', raw, now)
	self._dev:set_input_prop('w21003', 'RDATA', {
		value = val,
		value_src = raw,
		flag = convert_flag(flag, flag_o),
		timestamp = dtime -- TODO:
	}, now)
	self._dev:set_input_prop('sample_time', 'value', os.date('%FT%T', dtime), now)

	return true
end

function worker:read_state(modbus)
	local func = 0x03
	local addr = 0x2000
	local dlen = 0x0C

	local req, err = self._pdu:make_request(func, addr, dlen)
	if not req then
		return nil, err
	end
	local pdu, err = modbus:request(self._unit, req, 1000)
	if not pdu then
		return nil, err
	end

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		self._log:warning("read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1)))
		return nil, 'Modbus error'..d:uint8(pdu, 1)
	end

	local len = d:uint8(pdu, 2)
	assert(len >= dlen * 2, SF("length issue :%d - %d", len, dlen * 2))

	local pdu_data = string.sub(pdu, 3)

	local status = d:uint32(pdu_data, 1)
	local mode = d:uint16(pdu_data, 5)
	local alarm1 = d:uint16(pdu_data, 9)
	local alarm2 = d:uint16(pdu_data, 11) -- not used

	local i12101, rs = convert_status(status)
	local i12103 = convert_alarm(alarm1, alarm2)
	local i12102 = i12103 == 0 and 0 or 1

	local info, err = self:read_info(modbus)
	if not info then
		return nil, err
	end

	local now = ioe.time()
	for k, v in pairs(info) do
		self._dev:set_input_prop(k, 'value', v, now)
	end

	info.i12101 = i12101
	info.i12102 = i12102
	info.i12103 = i12103

	self._dev:set_input_prop('status', 'value', status, now)
	self._dev:set_input_prop('alarm', 'value', alarm1, now)
	self._dev:set_input_prop('RS', 'value', rs, now)

	self._dev:set_input_prop('i12101', 'value', i12101, now)
	self._dev:set_input_prop('i12103', 'value', i12103, now)

	self._dev:set_input_prop('w21003', 'INFO', info, now)
	return true
end

function worker:read_info(modbus)
	local func = 0x03
	local addr = 0x2200
	local dlen = 0x1F

	local req, err = self._pdu:make_request(func, addr, dlen)
	if not req then
		return nil, err
	end
	local pdu, err = modbus:request(self._unit, req, 1000)
	if not pdu then
		return nil, err
	end

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		self._log:warning("read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1)))
		return nil, 'Modbus error'..d:uint8(pdu, 1)
	end

	local len = d:uint8(pdu, 2)
	assert(len >= dlen * 2, SF("length issue :%d - %d", len, dlen * 2))

	local pdu_data = string.sub(pdu, 3)

	local i13121 = d:uint16(pdu_data, 1)
	local i13122 = d:uint16(pdu_data, 3)
	local calib_gap = d:uint16(pdu_data, 5) -- Hour
	local i13114 = d:uint16(pdu_data, 7)
	local range_min = d:float(pdu_data, 9)
	local i13116 = d:float(pdu_data, 13)
	local i13117 = d:float(pdu_data, 17)
	local i13102 = d:float(pdu_data, 21)
	local calib_tm = convert_datetime(pdu_data, 25)
	local i13104 = d:float(pdu_data, 33)
	local i13105 = d:float(pdu_data, 37)
	local i13108 = d:float(pdu_data, 41)
	local i13110 = d:float(pdu_data, 45)

	local kbrate = d:float(pdu_data, 57)
	local i13128 = d:uint16(pdu_data, 61)

	self._dev:set_input_prop('calib_time', 'value', os.date('%FT%T', calib_tm), now)

	return {
		i13101 = calib_tm,
		i13102 = i13102,
		i13104 = i13104,
		i13105 = i13105,
		i13107 = calib_tm,
		i13108 = i13108,
		i13110 = i13110,
		i13114 = i13114,
		i13116 = i13116,
		i13117 = i13117,
		i13121 = i13121,
		i13122 = i13122,
		i13128 = i13128,
	}
end

return worker
