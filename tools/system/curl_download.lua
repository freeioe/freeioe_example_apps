local lcurl_loaded, lcurl = pcall(require, 'lcurl')
local skynet = require 'skynet'
local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local helper = require 'utils.helper'
local lfs = require 'lfs'

local download = class('CURL_DOWNLOAD_CLASS')

function download:initialize()
end

local function fs_access(file)
	local mode = lfs.attributes(file, 'access')
	return mode
end

function download:wget_download(url, md5sum, save_path)
	if fs_access('/usr/bin/wget') then
		sysinfo.exec('wget -O '..save_path..' '..url)
	elseif fs_access('/usr/bin/curl') then
		sysinfo.exec('curl -o '..save_path..' '..url)
	else
		return false, 'wget/curl not found!!!!'
	end

	if fs_access(filepath) then
		local sum, err = helper.md5sum(save_path)
		if not sum then
			return nil, "Cannot caculate md5"
		end
		if string.lower(sum) ~= string.lower(md5sum) then
			return nil, "md5sum check failed"
		end
		return true
	end

	return false, 'Download file missing'
end

function download:download(url, md5sum, save_path, on_progress)
	if not lcurl_loaded then
		return self:wget_download(url, md5sum, save_path)
	end

	local headers = {}
	local f, err = io.open(save_path, 'w+')
	if not f then
		return nil, err
	end

	local easy_handle = lcurl.easy()
		:setopt_url(url)
		:setopt_httpheader({"Content-Type: application/x-www-form-urlencoded"})
		:setopt_writefunction(function(str) 
			f:write(str)
		end)
		:setopt_headerfunction(function(str)
			headers[#headers + 1] = str
		end)
		:setopt_progressfunction(function(ctx, total, downloaded, total_upload, uploaded)
			-- print(total, downloaded)
			on_progress(total, downloaded)
			return true
		end)
	
	local m = lcurl.multi():add_handle(easy_handle)

	while m:perform() > 0 do
		skynet.sleep(1)
		-- print('.')
		m:wait()
	end

	local h, r = m:info_read()
	--print(h, r)

	local failed = false
	if h ~= easy_handle or not r then
		falsed = true
	end
	easy_handle:close()
	f:close()

	if failed then
		--print('Failed to perform request')
		return nil, "Failed to perform request"
	end

	if md5sum then
		local sum, err = helper.md5sum(save_path)
		if not sum then
			return nil, "Cannot caculate md5"
		end
		if string.lower(sum) ~= string.lower(md5sum) then
			return nil, "md5sum check failed"
		end
	end
	--print('done')
	return true
end

return download
