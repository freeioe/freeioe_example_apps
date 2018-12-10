local class = require 'middleclass'
local ubus = require 'ubus'

local focas = class('FANUC_FOCAS_UBUS')

local function protected_call(ubus, ubus_name, method, param, on_success)
	local cjson = require 'cjson.safe'
	print(string.format('ubus call %s.%s :\t', ubus_name, method), cjson.encode(param))

	local r, ret, err = pcall(ubus.call, ubus, ubus_name, method, param)
	if not r then
		return nil, ret
	end

	local cjson = require 'cjson.safe'
	print('result', cjson.encode(ret))

	if not ret then
		return nil, ret
	else
		if ret.rc ~= 0 then
			return nil, ret.error
		else
			local r, err = on_success(ret)
			if not r and err then
				return nil, err
			end
			return r or true
		end
	end
end

--[[
local protected_call = function(ubus, ubus_name, method, param, on_success)
	local cjson = require 'cjson.safe'
	print(string.format('ubus [%s.%s] :\t', ubus_name, method), cjson.encode(param))
	if method == 'connect' then
		return {handle=1}
	end
	return {}
end
]]--

function focas:initialize(ip, port, name, sn, tpl)
	self._ip = ip
	self._port = port
	self._name = name
	self._sn = sn
	self._tpl = tpl
end

function focas:call(method, param, on_success)
	return protected_call(self._ubus, self._ubus_name, method, param, on_success)
end

function focas:connect(ubus, ubus_name)
	self._ubus = ubus
	self._ubus_name = ubus_name

	return self:call('connect', {ip=self._ip, port=self._port, timeout=5}, function(ret)
		print('connected', ret.handle)
		self._handle = ret.handle
		return true
	end)
end

function focas:disconnect()
	if not self._handle then
		return
	end
	return self:call('disconnect', {handle=self._handle}, function(ret)
		self._handle = nil
	end)
end

-- 设备信息
function focas:device_info()
	return nil, "not implemented"
end

-- 实际进给速率
function focas:actual_feed_rate()
	return self:call('actf', {handle=self._handle}, function(ret)
		return ret.data
	end)
end

-- 主轴转速
function focas:actual_rotational_speed()
	return self:call('acts', {handle=self._handle}, function(ret)
		return ret.data
	end)
end

-- 主轴转速
function focas:actual_rotational_speed2(index)
	return self:call('acts2', {handle=self._handle, index=index}, function(ret)
		if ret.index ~= -1 then
			return ret.data[ret.index]
		end
		return ret.data
	end)
end

-- 坐标
-- name:
-- absolute:	read absolute axis position */
-- machine:		read machine axis position */
-- machine2:	read machine axis position(2) */
-- machine3:	read machine axis position(3) */
-- distance:	read distance to go */
-- skip:		read skip position */
-- srvdelay:	read servo delay value */
-- accdecdly:	read acceleration/deceleration delay value */
-- absolute2:	read absolute axis position 2 */
-- relative2:	read relative axis position 2 */
-- distance2:	read distance to go(2) */
-- rd5axovrlap: read amount of machine axes movement of manual feed for 5-axis machining
-- allowance:	read allowance
function focas:axis(name, index,  index2)
	return self:call('axis', {handle=self._handle, ['function']=name, index=index, index2=index2}, function(ret)
		if ret.index ~= -1 then
			return ret.data[1]
		end
		return ret.data
	end)
end

--- 伺服负载百分比
function focas:read_servo_load_meter()
	return self:call('rdsvmeter', {handle=self._handle}, function(ret)
		return ret.data.svload.data
	end)
end

--- 主轴负载百分比
function focas:read_spindle_load_meter(spindle_type)
	return self:call('rdspmeter', {handle=self._handle, type=spindle_type}, function(ret)
		if spindle_type ~= -1 and #ret.data == 1 then
			return {
				load = ret.data[1].spload.data,
				speed = ret.data[1].spspeed.data
			}
		end
		return ret.data
	end)
end

--- 主轴名称
function focas:read_spindle_names()
	return self:call('rdspdlname', {handle=self._handle}, function(ret)
		return ret.data
	end)
end

--- 报警状态
function focas:read_alarm_status()
	return self:call('alarm', {handle=self._handle}, function(ret)
		return ret.status
	end)
end

function focas:read_alarm2_status()
	return self:call('alarm2', {handle=self._handle}, function(ret)
		return ret.status
	end)
end

--- 报警信息
function focas:read_alarm_info(alarm_type)
	return self:call('rdalminfo', {handle=self._handle, type=alarm_type}, function(ret)
		return ret.data
	end)
end

--- 报警消息
function focas:read_alarm_msg(alarm_type)
	return self:call('rdalmmsg', {handle=self._handle, type=alarm_type}, function(ret)
		return ret.data
	end)
end

function focas:read_alarm_msg2(alarm_type)
	return self:call('rdalmmsg2', {handle=self._handle, type=alarm_type}, function(ret)
		return ret.data
	end)
end

-- 错误值
function focas:read_detail_error()
	return self:call('getdtailerr', {handle=self._handle}, function(ret)
		return {
			errno = ret.err_no,
			detail_errno  = ret.err_dtno,
		}
	end)
end

-- 程序号
function focas:read_program_number()
	return self:call('rdprgnum', {handle= self._handle}, function(ret)
		return {
			running = ret.data,
			main = ret.mdata
		}
	end)
end

-- 当前执行程序
function focas:read_executing_program(length)
	return self:call('rdexecprog', {handle= self._handle}, function(ret)
		return {
			blknum = ret.blknum,
			length = ret.length,
			data = ret.data
		}
	end)
end

function focas:read_pmc(addr_type, data_type, start, length)
	local param = {
		handle = self._handle,
		addr_type = addr_type,
		data_type = data_type,
		start = start,
		length = length,
	}

	return self:call('rdpmcrng', param, function(ret)
		return ret.data
	end)
end

local function_ids = {
	device_info = 0,
	actual_feed_rate = 10,
	actual_rotational_speed = 11,
	actual_rotational_speed2 = 12,
	axis = 20,
	read_servo_load_meter = 30,
	read_spindle_load_meter = 31,
	read_spindle_names = 32,
	read_alarm_status = 40,
	read_alarm2_status = 41,
	read_alarm_info = 42,
	read_alarm_msg = 43,
	read_alram_msg2 = 44,
	read_detail_error = 50,
	read_program_number = 60,
	read_executing_program = 61,
	read_pmc = 70,
}

local function_inputs = {
	device_info = 'info',
	actual_feed_rate = 'actf',
	actual_rotational_speed = 'acts',
	actual_rotational_speed2 = 'acts2',
	axis = 'axis',
	read_servo_load_meter = 'svmeter',
	read_spindle_load_meter = {'load', 'speed'},
	read_spindle_names = 'spdlname',
	read_alarm_status = 'alarm',
	read_alarm2_status = 'alarm2',
	read_alarm_info = 'alarm_info',
	read_alarm_msg = 'alarm_msg',
	read_alram_msg2 = 'alarm_msg2',
	read_detail_error = {'errno', 'detail_errno'},
	read_program_number = {'running', 'main'},
	read_executing_program = 'prog',
	read_pmc = 'pmc',
}

focas.static.func_ids = function_ids

function focas:get_func_name(func)
	if type(func) == 'string' then
		return func
	end
	for k, v in pairs(function_ids) do
		if v == func then
			func = k
		end
	end
	return func
end

function focas:inputs(func, name, desc, vt, rate)
	local func = self:get_func_name(func)
	local names = function_inputs[func]
	if type(names) == 'string' then
		return {{
			name = name,
			desc = desc,
			vt = vt,
			rate = rate,
			vname = names,
		}}
	end

	local inputs = {}
	for _, v in ipairs(names) do
		table.insert(inputs, {
			name = name..'.'..v,
			desc = desc..' '..v,
			vt = vt,
			rate = rate,
			vname = v,
		})
	end
	return inputs
end

return focas

