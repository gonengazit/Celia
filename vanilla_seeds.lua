local balloon_seed = {}
local api = require("api")

balloon_seed.granularity=50
function balloon_seed.init(obj)
	obj.offset = 0
	obj.__tas_seed = 0
end
function balloon_seed.set_seed(obj, new_seed)
	obj.offset = obj.offset - obj.__tas_seed/balloon_seed.granularity + new_seed/balloon_seed.granularity
	obj.y=obj.start+api.sin(obj.offset)*2
	obj.__tas_seed = new_seed
end

function balloon_seed.increase_seed(obj)
	balloon_seed.set_seed(obj, (obj.__tas_seed+1)%balloon_seed.granularity)
end

function balloon_seed.decrease_seed(obj)
	balloon_seed.set_seed(obj, (obj.__tas_seed-1)%balloon_seed.granularity)
end


function balloon_seed.draw(obj)
	love.graphics.setColor(unpack(pico8.palette[1+9]))
	local x,y = math.floor(obj.x), math.floor(obj.y)
	love.graphics.rectangle("line", x-1, y-1, 10, 10)
	love.graphics.printf(tostring(obj.__tas_seed),x,y+11, 8 ,"center")
end

return {balloon = balloon_seed}
