--- 导入需要的模块
local modbus_slave = require 'modbus.slave.skynet'
local modbus_request = require 'modbus.pdu.request'
local modbus_response = require 'modbus.pdu.response'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'

local csv_tpl = require 'csv_tpl'
local data_block = require 'data_block'
local base_app = require 'app.base'
local cov = require 'cov'
local ioe = require 'ioe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = base_app:subclass("freeioe_example.modbus.slave_one_uint")
--- 设定应用最小运行接口版本
app.static.API_VER = 10

--- 应用启动函数
function app:on_start()
	self._cov = cov:new(function(...)
		self:handle_cov_data(...)
	end, {})
	self._cov:start()

	local log = self._log

	csv_tpl.init(self._sys:app_dir())

	---获取设备序列号和应用配置
	local sys_id = self._sys:id()
	--- Mapping 
	local function map_dev_sn(sn)
		if sn == 'GW' then
			return sys_id
		end
		local sn = sn or 'GW'
		sn = string.gsub(sn, '^GW(%..*)$', sys_id..'%1')
		return sn
	end

	local conf = self._conf or {}

	local tpl_id = conf.tpl
	local tpl_ver = conf.ver

	if conf.tpls and #conf.tpls >= 1 then
		tpl_id = conf.tpls[1].id
		tpl_ver = conf.tpls[1].ver
	end

	if tpl_id and tpl_ver then
		local capi = sys:conf_api(tpl_id)
		local data, err = capi:data(tpl_ver)
		if not data then
			log:error("Failed loading template from cloud!!!", err)
			return false
		end
		tpl_file = tpl_id..'_'..tpl_ver
	end

	if ioe.developer_mode() then
		conf.channel_type = 'socket'
		conf.socket_opt = {
			host = "0.0.0.0",
			port = 1503,
			nodelay = true
		}
		tpl_file = 'test'
	end

	log:info("Loading template", tpl_file)
	local tpl, err = csv_tpl.load_tpl(tpl_file, function(...)
		log:error(...)
	end)
	if not tpl then
		return nil, err
	end

	for _, v in ipairs(tpl.props) do
		v.sn = map_dev_sn(v.sn)
	end
	self._tpl = tpl

	self._request = modbus_request:new()
	self._response = modbus_response:new()
	self._data_pack = data_pack:new()
	self._data_unpack = data_unpack:new()

	self._block = data_block:new(self._data_pack, self._data_unpack, self._log)
	self._unit = tonumber(conf.unit) or 1 -- default is 1

	conf.channel_type = conf.channel_type or 'socket'
	if conf.channel_type == 'socket' then
		conf.opt = conf.socket_opt or {
			host = "0.0.0.0",
			port = 1503,
			nodelay = true
		}
	else
		conf.opt = conf.serial_opt or {
			port = "/tmp/ttyS1",
			baudrate = 19200
		}
	end

	if conf.channel_type == 'socket' then
		self._modbus = modbus_slave('tcp', {link='tcp', tcp=conf.opt})
	else
		if conf.ascii then
			self._modbus = modbus_slave('ascii', {link='serial', serial=conf.opt})
		else
			self._modbus = modbus_slave('rtu', {link='serial', serial=conf.opt})
		end
	end

	self._modbus:add_unit(self._unit, function(pdu, response)
		self:handle_pdu(response, self._request:unpack(pdu))
	end)

	--- 设定通讯口数据回调
	self._modbus:set_io_cb(function(io, unit, msg)
		--- 输出通讯报文
		if self._unit == tonumber(unit) then
			local dev_sn = sys_id.."."..self:app_name()
			self._sys:dump_comm(dev_sn, io, msg)
		else
			self._log:error('No dev for unit:'..unit)
			self._sys:dump_comm(sys_id, io, msg)
		end
	end)

	self._modbus:start()

	return true
end

function app:handle_pdu(response, fc, ...)
	if not fc then
		-- TODO:
		return
	end
	local h = self['handle_fc_0x'..string.format('%02X', fc)]
	if not h then
		-- TODO:
		return
	end

	return h(self, response, ...)
end

function app:handle_fc_0x01(response, addr, len)
	local block = self._block
	--self._log:trace('READ[0x01]', addr, len)
	local data = block:read(0x01, addr, len)
	local pdu = self._response:pack(0x01, string.len(data), data)
	return response(pdu)
end

function app:handle_fc_0x02(response, addr, len)
	local block = self._block
	--self._log:trace('READ[0x02]', addr, len)
	local data = block:read(0x02, addr, len)
	local pdu = self._response:pack(0x01, string.len(data), data)
	return response(pdu)
end

function app:handle_fc_0x03(response, addr, len)
	local block = self._block
	--self._log:trace('READ[0x03]', addr, len)
	local data = block:read(0x03, addr * 2, len * 2)
	local pdu = self._response:pack(0x03, string.len(data), data)
	return response(pdu)
end

function app:handle_fc_0x04(response, addr, len)
	local block = self._block
	--self._log:trace('READ[0x04]', addr, len)
	local data = block:read(0x04, addr * 2, len * 2)
	local pdu = self._response:pack(0x04, string.len(data), data)
	return response(pdu)
end

function app:handle_fc_0x05(response, addr, data)
	--- TODO: write prop
end

function app:handle_fc_0x06(response, addr, data)
	--- TODO: write prop
end

function app:handle_fc_0x0F(response, addr, len, data)
	--- TODO: write prop
end

function app:handle_fc_0x10(response, addr, len, data)
	--- TODO: write prop
end

--- 应用退出函数
function app:on_close(reason)
	if self._modbus then
		self._modbus:stop()
		self._modbus = nil
	end
	--print(self._name, reason)
end

function app:handle_cov_data(key, value, timestamp, quality)
	local sys_id = self._sys:id()
	local sn, input = string.match(key, '^([^/]+)/(.+)$')

	local props = self._tpl.props
	local block = self._block

	for _, v in ipairs(props) do
		if v.sn == sn and v.name == input then
			self._log:trace('write value to block', v.name, value)
			local r, err = block:write(v, value)
			if not r then
				self._log:debug('Value write failed!', err)
			end
		end
	end
end

function app:on_input(app_src, sn, input, prop, value, timestamp, quality)
	-- Skip quality not good value
	if quality ~= 0 or prop ~= 'value' then
		return
	end

	local props = self._tpl.props

	for _, v in ipairs(props) do
		if v.sn == sn and v.name == input then
			local key = sn..'/'..input
			self._cov:handle(key, value, timestamp, quality)
		end
	end
end

--- 返回应用对象
return app
