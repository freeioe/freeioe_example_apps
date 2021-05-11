local logger = require 'hj212.logger'
local crc16 = require 'hj212.utils.crc'
local base = require 'hj212.packet.data'

local pack = base:subclass('hj212.packet')

pack.static.HEADER	= '##' -- Packet Header fixed string
pack.static.TAIL	= '\r\n'
pack.static.MFMT = '##(%w+)\r\n()'

local function packet_crc(data_raw, crc_func)
	local f = crc_func or crc16
	return string.format('%04X', f(data_raw))
end

function pack.static.parse(raw, index, on_err, crc_func)
	local on_err = on_err or logger.error
	--logger.debug('begin', index, raw)
	local index = string.find(raw, pack.static.HEADER, index or 1, true)
	if not index then
		--- Incorrect stream, so trim stream
		if string.sub(raw, -1) == '#' then
			return nil, '#', 'Header(##) missing' --- Keep the last #
		end
		return nil, '', 'Header(##) missing'
	end

	local raw_len = string.len(raw)

	-- If stream is short than ##dddd
	if raw_len - index + 1 < 6 then
		if index > 1 then
			raw = string.sub(raw, index) -- trim stream
		end
		return nil, raw, 'Need more'
	end

	-- Read the data_len dddd from ##dddd
	local data_len = tonumber(string.sub(raw, index + 4 + 2, index + 4 + 5))
	if not data_len or data_len < 0 then
		--print(raw)
		local err = 'Stream length error, got:'..string.sub(raw, index + 4 + 2, index + 4 + 5)
		on_err(err)
		raw = string.sub(raw, index + 1) -- trim data
		return pack.static.parse(raw, 1, on_err, crc_func)
	end

	-- ##dddd....XXXX\r\n is 12 chars
	if data_len + 12 + 4 > raw_len - index + 1 then
		if index > 1 then
			raw = string.sub(raw, index) -- trim stream
		end
		local err = 'Stream not enough, data len:'..data_len..' stream len:'..raw_len..' head.index:'..index
		return nil, raw, err
	end

	--- Check TAIL
	local s_end = index + data_len + 2 + 4 + 4 + 4
	if string.sub(raw, s_end, s_end + 1) ~= pack.static.TAIL then 
		--print(raw)
		local err = 'Tailer<CR><LF> missing, received:'..string.sub(raw, s_end, s_end + 1)
		on_err(err)
		raw = string.sub(raw, index + 2) -- trim data
		return pack.static.parse(raw, 1, on_err, crc_func)
	end

	--- Get the packet data
	local s_data = index + 6 + 4
	local data_raw = string.sub(raw, s_data, s_data + data_len - 1)

	--- Get the crc
	local s_crc = s_data + data_len
	local crc = string.sub(raw, s_crc, s_crc + 3)

	local calc_crc = packet_crc(data_raw, crc_func)
	if calc_crc ~= crc then
		--print(raw)
		local err = string.format('CRC Error, calc:%s recv:%s', calc_crc, crc)
		on_err(err)
		raw = string.sub(raw, index + 2) -- trim data
		return pack.static.parse(raw, 1, on_err, crc_func)
	end

	--- Decode packet
	local obj = pack:new()
	obj:decode(data_raw)

	--print("DONE", raw)
	return obj, string.sub(raw, s_end + 2), 'Done'
end

function pack:initialize(...)
	base.initialize(self, ...)
end

function pack:encode_data(data)
	local len = string.len(data)

	local raw = {
		pack.static.HEADER
	}
	raw[#raw + 1] = string.format('%04d', len) -- 0000 ~ 9999
	raw[#raw + 1] = data
	raw[#raw + 1] = packet_crc(data)
	raw[#raw + 1] = pack.static.TAIL

	return table.concat(raw)
end

function pack:encode()
	local data = base.encode(self)

	if type(data) == 'string' then
		return self:encode_data(data)
	else
		local raw = {}
		for i, v in ipairs(data) do
			raw[#raw + 1] = self:encode_data(v)
		end
		return raw
	end
end

return pack
