local class = require 'middleclass'
local logger = require 'hj212.logger'
local types = require 'hj212.types'
local packet = require 'hj212.packet'
local pfinder = require 'hj212.utils.pfinder'

local client = class('hj212.server.client')

function client:initialize(pfuncs)
	self._station = nil
	self._system = nil
	self._dev_id = nil
	self._passwd = nil

	local pfuncs = pfuncs or {}
	self._packet_create = pfuncs.create or function(...)
		return packet:new(...)
	end
	self._packet_parse = assert(pfuncs.parse or packet.static.parse)
	self._packet_crc = pfuncs.crc
	self._packet_ver = assert(pfuncs.ver or types.PROTOCOL.V2017)

	self._process_buf = nil
	self._packet_buf = {}
	self._handlers = {}
	self._finders = {
		pfinder(types.COMMAND, 'hj212.server.handler')
	}
end

function client:log(level, ...)
	logger.log(level, ...)
end

function client:set_station(station)
	self._station = station
	if station then
		self._system = station:system()
		self._passwd = station:passwd()
		self._dev_id = station:id()
		--self._packet_ver = station:version()
	else
		self._system = nil
		self._passwd = nil
		self._dev_id = nil
	end
end

function client:station()
	return self._station
end

function client:req_creator(cmd, need_ack, params)
	return self._packet_create(self._packet_ver, self._system, cmd, self._passwd, self._dev_id, need_ack, params)
end

function client:resp_creator(cmd, need_ack, params)
	return self._packet_create(self._packet_ver, types.SYSTEM.REPLY, cmd, self._passwd, self._dev_id, need_ack, params)
end

function client:find_tag_sn(tag_name)
	local meter = self._station:find_tag_meter(tag_name)
	if meter then
		return meter:sn()
	end
end

function client:add_handler(packet_path_base)
	table.insert(self._finders, 1, pfinder(types.COMMAND, packet_path_base))
end

function client:__find_handler(cmd)
	for _, finder in pairs(self._finders) do
		local handler, err = finder(cmd)
		if handler then
			return handler
		end
	end
	return nil, "Command handler not found for CMD:"..cmd
end

function client:find_handler(cmd)
	if self._handlers[cmd] then
		return self._handlers[cmd]
	end

	local handler, err = self:__find_handler(cmd)
	if not handler then
		self:log('error', err)
		return nil, err
	end
	local h = handler:new(self)

	self._handlers[cmd] = h

	return h
end

function client:on_request(req)
	local cmd = req:command()
	local session = req:session()
	self:log('info', 'Received request', session, cmd)

	local handler, err = self:find_handler(cmd)

	if not handler then
		if req:need_ack() then
			self:send_reply(req:session(), types.REPLY.ERR_REJECT)
		end
		return
	end

	local result, err = handler(req)
	if not result then
		self:log('error', 'Process request failed', session, cmd, err)
		if req:need_ack() then
			self:send_reply(req:session(), types.REPLY.ERR_UNKNOWN)
		end
	else
		self:log('debug', 'Process request successfully', session, cmd)
		if req:need_ack() then
			self:send_ack(session)
		end
	end
end

function client:process(raw_data)
	local buf = self._process_buf and self._process_buf..raw_data or raw_data

	local p, buf, err = self._packet_parse(buf, 1, function(err)
		self:log('error', err)
	end, self._packet_crc)

	if buf and string.len(buf) > 0 then
		self._process_buf = buf
	else
		self._process_buf = nil
	end

	if not p then
		return nil, err or 'Not enough data'
	end

	if not self._station then
		self._system = p:system()
		self._passwd = p:password()
		self._dev_id = p:device_id()
		self._packet_ver = p:version()
		local station, reply_code = self:on_station_create(p:system(), p:device_id(), p:password(), p:version())
		if not station then
			self:log('error', 'REPLY_CODE', reply_code)
			self:send_reply(p:session(), reply_code)
			return nil, 'Station create failed, code: '..reply_code
		end
		self._station = station
	end

	for k, buf in pairs(self._packet_buf) do
		local now = os.time()
		local timeout = true
		for i, p in pairs(buf) do
			if now - p:sub_time() < 360 then
				timeout = false
				break
			end
		end
		if timeout then
			-- Remove buffer
			self:log('debug', 'Multiple packet timeout', k)
			self._packet_buf[k] = nil
		end
	end

	-- Sub packets 
	if p:total() > 1 then
		-- disable sub compact for now
		--[[
		local session = p:session()
		local cur, cur_data = p:cur_data()
		local buf = self._packet_buf[session] and self._packet_buf[session] or {}
		buf[cur] = p --- may overwrite the old received one
		if #buf < p:total() then
			self:log('debug', 'Multiple packet found', p._total, cur)
			--- TODO: self:data_ack(session)
			return nil, "Mutiple packets found!!"
		end
		self:log('debug', 'Multiple packet completed', p._total, cur)
		p = buf[1]
		for i = 2, p:total() do
			p:sub_append(buf[i]:cur_data())
		end
		]]--
		p:sub_done()
	end

	if p:system() == types.SYSTEM.REPLY then
		self:log('debug', 'On reply', p:session(), p:command())
		return p, true
	else
		local ss = p:session()
		ss = ss // 1000
		self:log('debug', 'On request', p:session(), p:command())
		return p, false
	end
end

function client:reply(reply)
	local r, pack = pcall(reply.encode, reply, function(...)
		return self:resp_creator(...)
	end)

	if r then
		assert(pack:system() == types.SYSTEM.REPLY)
		assert(not pack:need_ack())

		local raw = pack:encode()
		if type(raw) == 'table' then
			raw = table.concat(raw)
		end

		local r, err = self:send_nowait(raw)
		if not r then
			self:log('error', err or 'EEEEEEEEEEEEEE2222')
			return nil, err
		end
		return true
	else
		self:log('error', pack or 'EEEEEEEEEEEEEE')
		return nil, pack
	end
end

function client:request(req, response)
	local r, pack = pcall(req.encode, req, function(...)
		return self:req_creator(...)
	end)

	if not r then
		self:log('error', pack or 'EEEEEEEEEEEEEE')
		return nil, pack
	end

	assert(pack:system() ~= types.SYSTEM.REPLY)
	local raw = pack:encode()
	if not pack:need_ack() then
		assert(not response)
		if type(raw) == 'table' then
			raw = table.concat(raw)
		end
		return self:send_nowait(raw)
	else
		local session = pack:session()
		--- Single packet
		if type(raw) == 'string' then
			local r, err = self:send(session, raw)
			if response and r then
				r, err = response(r, err)
			end
			return r, err
		end

		--- Mutiple packets which need ack for each
		for i, v in ipairs(raw) do
			local r, err = self:send(session + i, v)
			if response and r then
				r, err = response(r, err)
			end
			if not r then
				return nil, err
			end
		end
		return true
	end
end
function client:send_reply(session, reply_status)
	assert(session, "session missing")
	assert(reply_status, "Status missing")
	local reply = require 'hj212.reply.reply'
	local resp = reply:new(session, reply_status)
	self:log('debug', "Sending reply", reply_status)
	return self:reply(resp)
end

function client:send_ack(session)
	local reply = require 'hj212.reply.data_ack'
	local resp = reply:new(session)
	self:log('debug', "Sending data ack")
	return self:reply(resp)
end

function client:send_notice(session)
	local notice = require 'hj212.reply.notice'
	local resp = notice:new(session)
	self:log('debug', "Sending notice")
	return self:reply(resp)
end

function client:send(session, raw_data)
	assert(nil, 'Not implemented')
end

function client:send_nowait(raw_data)
	assert(nil, 'Not implemented')
end

function client:close()
	assert(nil, 'Not implemented')
end

function client:on_station_create(system, dev_id, passwd, packet_ver)
	assert(nil, 'Not implemented')
end

return client
