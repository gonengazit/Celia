format = require"FormatIdentity"
parse = require"ParseLua"


local f = io.open("celeste.lua","r")
local data= f:read("*all")

local st, main = parse.ParseLua(data)
print(st,main)
if st then
	print(format(main))
end
love.event.quit()
