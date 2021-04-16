local cjson = require 'cjson.safe'
local date = require 'date'
local lfs = require 'lfs'
local ioe = require 'ioe'
local crypt = require 'skynet.crypt'

local _M = {
	dir = '/tmp/egg'
}

function _M.init(folder)
	_M.dir = folder
	lfs.mkdir(folder)
end

local function decode_image(pic)
	local tp, en, data = string.match(pic, '^data:([^;]+);([^,]+),(.+)$')
	if en == 'base64' then
		data = crypt.base64decode(data)
	end
	if tp == 'image/jpeg' then
		--return 'jpeg', data
		return 'bmp', data -- The data alwasys BMP format, and the type is fixed.
	end
	return 'unknown', data
end

function _M.save(data)
	local tm = date(data.info.CreateTime)
	local fn = tm:fmt("%Y_%m_%d_T_%H%M%S")
	local mf, err = io.open(_M.dir..'/'..fn..'.meta', 'w')
	if not mf then
		return nil, err
	end

	mf:write(cjson.encode(data.info))
	mf:close()

	if data.SanpPic then
		local tp, data = decode_image(data.SanpPic)
		local ffn = string.format(_M.dir..'/%s.snap.%s', fn, tp)
		local pic, err = assert(io.open(ffn, 'w'))
		pic:write(data)
		pic:close()
	end
	if data.RegisteredPic then
		local tp, data = decode_image(data.RegisteredPic)
		local ffn = string.format(_M.dir..'/%s.reg.%s', fn, tp)
		local pic, err = assert(io.open(ffn, 'w'))
		pic:write(data)
		pic:close()
	end
	return true
end


return _M

