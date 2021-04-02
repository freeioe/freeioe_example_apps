local class = require 'middleclass'
local date = require 'date' -- date module for encoding/decoding
local time = require 'hj212.utils.time'
local params = require 'hj212.params'

local data = class('hj212.data')

local date_fmt = '%Y%m%d%H%M%S'

function data:initialize(ver, sys, cmd, passwd, devid, need_ack, params)
	self._session = math.floor(time.now())
	self._ver = ver
	self._sys = sys
	self._cmd = cmd
	self._passwd = passwd
	self._devid = devid
	self._need_ack = need_ack
	self._params = params
end

-- TODO: Packet spilit
function data:encode()
	assert(string.len(self._passwd) == 6)
	assert(string.len(self._devid) > 0) -- == 24) -- The standard is 24 char len, but we need to support exceptions :-(
	assert(self._sys >= 0 and self._sys <= 99)

	local flag = (self._ver << 2 ) + (self._need_ack and 1 or 0)

	local function encode(data, count, cur)
		-- Hack the session with plus ticks
		local session = self._session
		if cur and self._need_ack then
			session = session + cur	
		end
	
		local time = session // 1000
		local ticks = session % 1000
		local qn = date(time):tolocal():fmt(date_fmt) .. string.format('%03d', ticks)

		local raw = {}
		raw[#raw + 1] = string.format('QN=%s', qn)
		raw[#raw + 1] = string.format('ST=%02d', self._sys)
		raw[#raw + 1] = string.format('CN=%04d', self._cmd)
		raw[#raw + 1] = string.format('PW=%s', self._passwd)
		raw[#raw + 1] = string.format('MN=%s', self._devid)

		if count then
			raw[#raw + 1] = string.format('Flag=%s', string.format('%d', flag + 2))
			raw[#raw + 1] = string.format('PNUM=%d', count)
			raw[#raw + 1] = string.format('PNO=%d', cur)
		else
			raw[#raw + 1] = string.format('Flag=%s', string.format('%d', flag))
		end

		raw[#raw + 1] = string.format('CP=&&%s&&', data)
		return table.concat(raw, ';')
	end

	local pdata = self._params:encode()

	if type(pdata) == 'table' then
		local count = #pdata
		if count == 1 then
			return encode(pdata[1])
		end

		local t = {}
		for i, v in ipairs(pdata) do
			t[#t + 1] = encode(v, count, i)
		end
		return t
	else
		return encode(pdata)
	end
end

function data:decode(raw, index)
	local head, params_data, index = string.match(raw, '^(.-)CP=&&(.-)&&()', index)
	if not head or not params_data then
		return nil, "Invalid packet data"
	end

	local qn = string.match(raw, 'QN=([^;]+)')
	if qn then
		qn = string.sub(qn, 1, -4)..'.'..string.sub(qn, -3)
		self._session = math.floor(date.diff(date(qn):toutc(), date(0)):spanseconds() * 1000)
	else
		self._session = os.time() * 1000 + math.random(0, 999)
	end

	self._sys = tonumber(string.match(raw, 'ST=(%d+)'))
	self._cmd = tonumber(string.match(raw, 'CN=(%d+)'))
	self._passwd = string.match(raw, 'PW=([^;]+)')
	self._devid = string.match(raw, 'MN=([^;]+)')
	local flag = tonumber(string.match(raw, 'Flag=(%d+)')) or 0 --- For invalid Flag found in protocol
	self._ver = flag >> 2
	self._need_ack = ((flag & 1) == 1)

	--- Packet spilit not supported

	if ((flag & 0x3) >> 1) == 1 then
		--assert(nil, "Packet split not support")
		self._params_data = params_data

		local total = tonumber(string.match(raw, 'PNUM=(%d+)') or '')
		if total == 1 or not total then
			self:sub_done()
			return index
		end

		local cur = tonumber(string.match(raw, 'PNO=(%d+)') or '')
		assert(total ~= nil and cur ~= nil, "PNUM or PNO missing")
		self._total = total
		self._sub = cur
		self._sub_time = os.time()
	else
		if not self._params then
			self._params = params:new()
		end
		self._params:decode(params_data)
	end
	return index
end

function data:total()
	return self._total or 1
end

function data:cur_data()
	return self._sub, self._params_data
end

function data:sub_time()
	return self._sub_time
end

function data:sub_append(p)
	assert(self._sub == 1)
	local index, pdata = p:cur_data()
	assert(pdata, "Param data missing")
	self._last_append = self._last_append or 1
	assert(self._last_append + 1 == index)
	self._last_append = index

	self._params_data = self._params_data..pdata
end

function data:sub_done()
	if not self._params then
		self._params = params:new()
	end
	self._params:decode(self._params_data)
end

function data:session()
	return self._session
end

function data:set_session(session)
	self._session = session
end

function data:system()
	return self._sys
end

function data:command()
	return self._cmd
end

function data:password()
	return self._passwd
end

function data:device_id()
	return self._devid
end

function data:version()
	return self._ver
end

function data:need_ack()
	return self._need_ack
end

function data:params()
	return self._params
end

return data
