local time = {}

local skynet_loaded, skynet = pcall(require, 'skynet')

--- Default time now
time.now = function()
	if skynet_loaded then
		return math.floor(skynet.time() * 1000)
	end
	return os.time() + math.random(1000)
end

return time
