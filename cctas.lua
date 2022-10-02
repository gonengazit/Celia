local tas = require("tas")

local cctas = tas:extend("cctas")

function cctas:init()
	--this seems hacky, but is actually how updation order behaves in vanilla
	pico8.cart.begin_game()
	pico8.cart._draw()
	self.super.init(self)

	self.level_time=0

	self:state_changed()
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

	self.level_time=0
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

function cctas:find_player()
	for _,v in ipairs(pico8.cart.objects) do
		if v.type==pico8.cart.player then
			return v
		end
	end
end

function cctas:step()
	self.super.step(self)

	if self:find_player() then
		self.level_time = self.level_time + 1
	end
	self:state_changed()
end

function cctas:rewind()
	self.super.rewind(self)
	if self.level_time>0 then
		self.level_time= self.level_time-1
	end
	self:state_changed()
end

function cctas:full_rewind()
	self.super.full_rewind(self)

	self.level_time=0
	self:state_changed()
end

function cctas:clearstates()
	self.super.clearstates(self)

	self:state_changed()
end

function cctas:frame_count()
	return self.level_time
end

function cctas:state_changed()
	self.inputs_active=self.level_time~=0 or self:predict(self.find_player,1)
end

function cctas:draw_button(...)

	if not self.inputs_active then
		return
	end
	self.super.draw_button(self,...)
end

return cctas

