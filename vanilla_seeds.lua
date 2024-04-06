local balloon_seed = {}
local api = require("api")

balloon_seed.granularity=50

function balloon_seed.inject(type)
end

function balloon_seed.init(obj)
	obj.offset = 0
	obj.__tas_seed = 0
end
function balloon_seed.set_seed(obj, new_seed)
	obj.offset = obj.offset - obj.__tas_seed + new_seed
	obj.y=obj.start+api.sin(obj.offset)*2
	obj.__tas_seed = new_seed
end

function balloon_seed.increase_seed(obj)
	balloon_seed.set_seed(obj, (obj.__tas_seed + 1/balloon_seed.granularity)%1)
end

function balloon_seed.decrease_seed(obj)
	balloon_seed.set_seed(obj, (obj.__tas_seed-1/balloon_seed.granularity)%1)
end


function balloon_seed.draw(obj)
	setPicoColor(9)
	local x,y = math.floor(obj.x), math.floor(obj.y)
	love.graphics.rectangle("line", x-1, y-1, 10, 10)
	love.graphics.printf(tostring(math.floor(obj.__tas_seed*balloon_seed.granularity + 0.5)),x,y+11, 8 ,"center")
end

local chest_seed = {}

function chest_seed.inject(pico8)
	local _upd = pico8.cart.chest.update
	pico8.cart.chest.update = function(this)
		local _rnd = pico8.cart.rnd
		if this.timer <= 1 then
			pico8.cart.rnd = function()
				--add a small value becase noninteger rng values give the berry a slightly bigger hitbox
				return this.__tas_seed + 1 + 0x0.0001
			end
		end
		_upd(this)
		pico8.cart.rnd = _rnd
	end
end

function chest_seed.init(obj)
	-- make sure not to double inject
	obj.__tas_seed = 0
end
function chest_seed.set_seed(obj, new_seed)
	obj.__tas_seed = new_seed
end

function chest_seed.increase_seed(obj)
	chest_seed.set_seed(obj, (obj.__tas_seed+2)%3-1)
end

function chest_seed.decrease_seed(obj)
	chest_seed.set_seed(obj, (obj.__tas_seed)%3-1)
end


function chest_seed.draw(obj)
	setPicoColor(9)
	local x,y = math.floor(obj.x) + obj.__tas_seed, math.floor(obj.y)
	love.graphics.rectangle("line", x-1, y-1, 10, 10)
	love.graphics.printf(tostring(obj.__tas_seed),x,y+11, 8 ,"center")
end

return {balloon = balloon_seed, chest=chest_seed}
