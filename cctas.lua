local tas = require("tas")

local cctas = tas:extend("cctas")

function cctas:init()
	--this seems hacky, but is actually how updation order behaves in vanilla
	pico8.cart.begin_game()
	pico8.cart._draw()
	self.super.init(self)

	self.level_time=0

	self.prev_obj_count=0
	self.modify_loading_jank=false
	self.first_level=self:level_index()
	self.loading_jank_offset=#pico8.cart.objects+1

	self:state_changed()
end

function cctas:toggle_key(i)
	-- don't allow changing the inputs while the player is dead
	if not self.inputs_active then
		return
	end
	self.super.toggle_key(self, i)
end

function cctas:keypressed(key, isrepeat)
	if self.realtime_playback then
		self.super.keypressed(self,key,isrepeat)
	elseif self.modify_loading_jank then
		self:loading_jank_keypress(key,isrepeat)
	elseif key=='a' and not isrepeat then
		self.modify_loading_jank = true
		self:full_rewind()
	elseif key=='f' then
		self:next_level()
	elseif key=='s' then
		self:prev_level()
	elseif key=='d' and love.keyboard.isDown('lshift', 'rshift') then
		self:player_rewind()
	else
		self.super.keypressed(self,key,isrepeat)
	end
end

function cctas:loading_jank_keypress(key,isrepeat)
	if key=='up' then
		self.loading_jank_offset = math.min(self.loading_jank_offset +1, math.max(#pico8.cart.objects-self.prev_obj_count + 1,0))
	elseif key == 'down' then
		self.loading_jank_offset = math.max(self.loading_jank_offset - 1, math.min(-self.prev_obj_count+1,0))
	elseif key == 'a' and not isrepeat then
		self.modify_loading_jank = false
		self:load_level(self:level_index(),false)
	end

end

function cctas:reset_vars()
	self.hold=0
end

local function load_room_wrap(idx)
	--TODO: support evercore style carts
	pico8.cart.load_room(idx%8, math.floor(idx/8))
end
function cctas:load_level(idx, reset_loading_jank)
	--apply loading jank
	load_room_wrap(idx-1)
	self.prev_obj_count=0
	for _,obj in ipairs(pico8.cart.objects) do
		-- assume room title is destroyed before you exit the level
		-- assume no other objects will be destroyed before you exit the level
		-- (this is easy to tweak with the offset variable)
		if obj.type ~= pico8.cart.room_title or pico8.cart.room_title==nil then
			self.prev_obj_count = self.prev_obj_count + 1
		end
	end
	load_room_wrap(idx)
	if reset_loading_jank then
		-- for the first level, assume no objects get loading janked by default
		self.loading_jank_offset = self:level_index() == self.first_level and #pico8.cart.objects + 1 or 0
	end

	for i = self.prev_obj_count+ self.loading_jank_offset, #pico8.cart.objects do
		local obj = pico8.cart.objects[i]
		if obj ~= nil then
			obj.move(obj.spd.x,obj.spd.y)
			if obj.type.update~=nil then
				obj.type.update(obj)
			end
		end
	end

	pico8.cart._draw()

	self.level_time=0
	self:clearstates()
	self:reset_vars()
end
function cctas:level_index()
	return pico8.cart.level_index()
end
function cctas:next_level()
	self:load_level(self:level_index()+1,true)
end
function cctas:prev_level()
	self:load_level(self:level_index()-1,true)
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
	self:reset_vars()
end

function cctas:player_rewind()
	if self.level_time>0 or self.inputs_active then
		for _ = 1, self.level_time do
			self:popstate()
			self.level_time = self.level_time- 1
		end
		pico8=self:peekstate()
	else
		while not self.inputs_active do
			--TODO: make this performant, animated, or remove this
			self:step()
		end
	end
	self:reset_vars()
end

function cctas:clearstates()
	self.super.clearstates(self)

	self:state_changed()
end

function cctas:frame_count()
	return self.level_time
end

function cctas:state_changed()
	self.inputs_active=self:predict(self.find_player,1)
end

function cctas:draw_button(...)

	if not self.inputs_active then
		return
	end
	self.super.draw_button(self,...)
end

function cctas:hud()
	local p=self:find_player()
	if p == nil then
		return ""
	end
	return ("%6s%7s\npos:% -7g% g\nrem:% -7.3f% .3f\nspd:% -7.3f% .3f\n\ngrace: %d"):format("x","y",p.x,p.y,p.rem.x,p.rem.y, p.spd.x, p.spd.y, p.grace)
end

function cctas:draw()
	self.super.draw(self)

	love.graphics.print(self:hud(),1,13,0,2/3,2/3)

	if self.modify_loading_jank then
		love.graphics.push()
		love.graphics.translate(self.hud_w,self.hud_h)

		for i = self.prev_obj_count + self.loading_jank_offset, #pico8.cart.objects do
			local obj = pico8.cart.objects[i]
			if obj~=nil then
				love.graphics.setColor(unpack(pico8.palette[6+1]))
				love.graphics.rectangle('line', obj.x-1, obj.y-1, 10,10)
			end
		end
		love.graphics.pop()

		love.graphics.setColor(255,255,255)
		love.graphics.printf(('loading jank offset: %+d'):format(self.loading_jank_offset),1,100,48,"left",0,2/3,2/3)
	end

end

return cctas

