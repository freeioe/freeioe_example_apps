local class = require 'middleclass'

local logger = {}

-- Default is print
logger.print = function(...)
	print(...)
end

logger.dump = function(info, raw, index)
	local r, basexx = pcall(require, 'basexx')
	if r then
		if index then
			logger.print(info, basexx.to_hex(string.sub(raw, index)))
		else
			logger.print(info, basexx.to_hex(raw))
		end
	end
end

local _log

logger.set_log = function(f)
	_log = f
end

logger.log = function(level, fmt, ...)
	if not _log then
		logger.print(level, string.format(fmt, ...))
	else
		_log(level, fmt, ...)
	end
end

logger.error = function(...)
	logger.log('error', ...)
end

logger.info = function(...)
	logger.log('info', ...)
end

logger.notice = function(...)
	logger.log('notice', ...)
end

logger.warning = function(...)
	logger.log('warning', ...)
end

logger.debug = function(...)
	logger.log('debug', ...)
end

return logger
