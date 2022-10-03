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

function cctas:load_level(idx)
	--TODO: support evercore style carts
	pico8.cart.load_room(idx%8, math.floor(idx/8))
	--TODO: handle loading jank here
	pico8.cart._draw()

	self.level_time=0
	self:clearstates()
end
function cctas:level_index()
	return pico8.cart.level_index()
end
function cctas:next_level()
	self:load_level(self:level_index()+1)
end
function cctas:prev_level()
	self:load_level(self:level_index()-1)
end

function cctas:find_player()
	for _,v in ipairs(pico8.cart.objects) do
		if v.type==pico8.cart.player then
			return v
		end
	end
end

function cctas:step()
	local lvl_idx=self:level_index()
	self.super.step(self)

	if lvl_idx~=self:level_index() then
		-- self:load_level(lvl_idx)
		-- TODO: make it so clouds don't jump??
		self:full_rewind()
		return
	end

	if self.level_time>0 or self:find_player() then
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

