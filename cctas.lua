local tas = require("tas")

local cctas = tas:extend("cctas")

function cctas:init()
	--this seems hacky, but is actually how updation order behaves in vanilla
	pico8.cart.begin_game()
	pico8.cart._draw()
	self.super.init(self)
end

function cctas:keypressed(key, isrepeat)
	if self.realtime_playback then
		self.super.keypressed(self,key,isrepeat)
	elseif key=='f' then
		self:next_level()
	elseif key=='s' then
		self:prev_level()
	else
		self.super.keypressed(self,key,isrepeat)
	end
end

function cctas:load_level(x,y)
	--TODO: support evercore style carts
	pico8.cart.load_room(x, y)
	--TODO: handle loading jank here
	pico8.cart._draw()
	self:clearstates()
end
function cctas:next_level()
	local x,y=pico8.cart.room.x, pico8.cart.room.y
	self:load_level((x+1)%8, y+math.floor((x+1)/8))
end
function cctas:prev_level()
	local x,y=pico8.cart.room.x, pico8.cart.room.y
	self:load_level((x-1)%8, y+math.floor((x-1)/8))
end

return cctas
