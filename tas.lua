require "deepcopy"
local api = require("api")

local tas = {}

local states={}


function tas.load()
end

function tas.update()
end

function tas.draw()
end

local function get_api_funcs(t, seen, visited)
	visited=visited or {}
	if visited[t] then
		return
	end
	visited[t]=true
	if(t==pico8) then
		return
	elseif seen[t] then
		return
	elseif type(t) == "function" then
		seen[t]=t
	elseif type(t) == "table" then
		for k,v in pairs(t) do
			get_api_funcs(v,seen, visited)
		end
	end
end

function tas.step()
	-- don't copy any non-cart functions
	local api_funcs={}
	get_api_funcs(_G, api_funcs)
	table.insert(states, deepcopy(pico8, api_funcs))

	if pico8.cart._update60 then
		pico8.cart._update60()
	elseif pico8.cart._update then
		pico8.cart._update()
	end

	if pico8.cart._draw then
		pico8.cart._draw()
	end
end

function tas.rewind()
	-- takes 2 steps back, then 1 forward
	-- the alternative is to save the screen
	-- probably better, but i don't know how to do it.
	if #states < 2 then
		return
	end

	table.remove(states)
	local prev_state = table.remove(states)
	pico8=prev_state
	tas.step()
end


return tas
