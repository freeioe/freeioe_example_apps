--- CRC16
--

return function(adu)
	local crc;

	local function initCrc()
		crc = 0xffff;
	end
	local function updCrc(byte)
		crc = crc ~ byte
		for i = 1, 8 do
			local j = crc & 1
			crc = crc >> 1
			if j ~= 0 then
				crc = crc ~ 0xA001
			end
		end
	end

	local function getCrc(adu)
		initCrc();
		for i = 1, #adu  do
			updCrc(adu:byte(i));
		end
		return (crc >> 8) + ((crc & 0xFF) << 8)
	end
	return getCrc(adu);
end
