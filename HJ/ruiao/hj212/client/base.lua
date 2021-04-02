local class = require 'middleclass'
local logger = require 'hj212.logger'
local types = require 'hj212.types'
local packet = require 'hj212.packet'
local pfinder = require 'hj212.utils.pfinder'

local client = class('hj212.client.base')

function client:initialize(station, passwd, timeout, retry, pfuncs)
	assert(station and passwd)
	self._station = station
	self._system = tonumber(station:system())
	self._dev_id = station:id()
	self._passwd = passwd
	self._rdata_enable = true
	self._timeout = (tonumber(timeout) or 5) * 1000
	self._retry = tonumber(retry) or 3

	local pfuncs = pfuncs or {}
	self._packet_create = pfuncs.create or function(...)
		return packet:new(...)
	end
	self._packet_parse = assert(pfuncs.parse or packet.static.parse)
	self._packet_crc = pfuncs.crc
	self._packet_ver = assert(protocal_ver or types.PROTOCOL.V2017)

	self._process_buf = nil
	self._handlers = {}
	self._finders = {
		pfinder(types.COMMAND, 'hj212.client.handler')
	}
end

function client:log(level, ...)
	logger.log(level, ...)
end

function client:station()
	return self._station
end

function client:system()
	return self._system
end

function client:device_id()
	return self._dev_id
end

function client:passwd()
	return self._passwd
end

function client:set_passwd(passwd)
	self._passwd = passwd
end

function client:timeout()
	return self._timeout
end

function client:set_timeout(timeout)
	self._timeout = timeout
end

function client:retry()
	return self._retry
end

function client:set_retry(retry)
	self._retry = retry
end

function client:rdata_enable()
	return self._rdata_enable
end

function client:set_rdata_enable(enable)
	self._rdata_enable = enable
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

function client:on_request(request)
	local cmd = request:command()
	local session = request:session()
	self:log('info', 'Received request', session, cmd)

	local handler, err = self:find_handler(cmd)

	if not handler then
		self:send_reply(session, types.REPLY.REJECT)
		return
	end

	if request:need_ack() then
		self:send_reply(session, types.REPLY.RUN)
	end

	local result, err = handler(request)
	if not result then
		self:log('error', 'Process request failed', session, cmd, err)
	else
		self:log('debug', 'Process request successfully', session, cmd)
	end

	self:send_result(session, result and types.RESULT.SUCCESS or types.RESULT.ERR_UNKNOWN)
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
	assert(p:total() == 1, "Packet split not supported!!")

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

function client:send(session, raw_data)
	assert(nil, 'Not implemented')
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

function client:request(request, response)
	local r, pack, err = pcall(request.encode, request, function(...)
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
	local reply = require 'hj212.reply.reply'
	local resp = reply:new(session, reply_status)
	self:log('debug', "Sending reply", reply_status)
	return self:reply(resp)
end

function client:send_result(session, result_status)
	local result = require 'hj212.reply.result'
	local resp = result:new(session, result_status)
	self:log('debug', "Sending result", result_status)
	return self:reply(resp)
end

function client:send_notice(session)
	local notice = require 'hj212.reply.notice'
	local resp = notice:new(session)
	self:log('debug', "Sending notice")
	return self:reply(resp)
end

function client:send_nowait(raw_data)
	assert(nil, 'Not implemented')
end

function client:connect()
	assert(nil, 'Not implemented')
end

function client:close()
	assert(nil, 'Not implemented')
end

function client:handle(cmd, ...)
	if self.on_command then
		return self.on_command(cmd, ...)
	end
	for k, v in pairs(types.COMMAND) do
		if v == cmd then
			local fn = 'on_command_'..string.lower(k)
			if self[fn] then
				return self[fn](self, ...)
			end
		end
	end
	return false, 'Not implemented'
end

return client
