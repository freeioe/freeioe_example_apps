local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local CALC_MAX_ARGS = 10

local function load_tpl(name, err_cb)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local meta = {}
	local calcs = {}
	local props = {}

	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'META' then
				meta.name = v[2]
				meta.desc = v[3]
				meta.series = v[4]
			end
			if v[1] == 'CALC' then
				local calc = {
					name = v[2],
					desc = v[3],
					enabled = tonumber(v[6]) == 1,
				}
				if string.len(v[4]) > 0 then
					calc.unit = v[4]
				end
				if string.len(v[5]) > 0 then
					calc.rw = v[5]
				end
				calc.func = v[7]

				calc.args = {}
				for i = 1, CALC_MAX_ARGS do
					calc.args[i] = v[7 + i]
				end
				calcs[#calcs + 1] = calc
			end
			if v[2] == 'PROP' then
				local prop = {
					name = v[2],
					desc = v[3],
					enabled = tonumber(v[5]) == 1,
				}
				if string.len(v[4]) > 0 then
					prop.unit = v[4]
				end
				if string.len(v[5]) > 0 then
					prop.rw = v[5]
				end
				props[#props + 1] = prop
			end
		end
	end

	return {
		meta = meta,
		calcs = calcs,
		props = props
	}
end

local function load_calc_func(name, ...)
	local r, m, err = pcall(require, 'smc_calc.'..name)
	if not r or not m then
		return nil, m or err
	end
	return m:new(...)
end

local function map_mode(mode_tpl, dev_tpl, err_cb)
	local tpl = {}
	tpl.meta = setmetatable(dev_tpl.meta, { __index = mode_tpl })
	local dev_props = {}
	for _, prop in ipairs(dev_tpl.props) do
		if prop.enabled  then
			dev_props[prop.name] = prop
		end
	end
	for _, calc in ipairs(dev_tpl.calcs) do
		if calc.enabled then
			local prop = {
				name = calc.name,
				desc = calc.desc,
				unit = calc.unit,
				enabled = calc.enabled,
				rw = calc.rw,
				func = load_calc_func(calc.func, table.unpack(calc.args))
			}
			if calc.func and not prop.func then
				err_cb(string.format("Loading function %s failed", calc.func))
			end
			dev_props[prop.name] = calc
		end
	end

	tpl.props = {}
	for _, prop in ipairs(mode_tpl.props) do
		local dp = dev_props[prop.name]
		if dp and dp.enabled then
			table.insert(tpl.props, setmetatable(dp, { __index = prop }))
		end
	end

	return tpl
end

return {
	load_tpl = load_tpl,
	map_mode = map_mode,
	init = function(dir)
		tpl_dir = dir.."/tpl/"
	end
}
