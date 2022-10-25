local tas = require("tas")

local cctas = tas:extend("cctas")

local vanilla_seeds = require("vanilla_seeds")
local api = require("api")

local console = require("console")


--TODO: probably call load_level directly
--or at least make sure rng seeds are set etc
function cctas:init()

	for type, seed in pairs(vanilla_seeds) do
		if pico8.cart[type] ~= nil then
			seed.inject(pico8)
		end
	end

	-- add tostring metamethod to objects, for use with the console
	local init_object = pico8.cart.init_object
	pico8.cart.init_object = function(...)
		local o = init_object(...)

		local mt = getmetatable(o) or {}
		mt.__tostring = function(obj)
			local type = "object"
			for k,v in pairs(pico8.cart) do
				if obj.type == v then
					type = k
					break
				end
			end
			return ("[%s] x: %g, y: %g, rem: {%g, %g}, spd: {%g, %g}"):format(type, obj.x, obj.y, obj.rem.x, obj.rem.y, obj.spd.x, obj.spd.y)
		end
		setmetatable(o, mt)
		return o
	end

	--this seems hacky, but is actually how updation order behaves in vanilla
	pico8.cart.begin_game()
	pico8.cart._draw()

	self.level_time=0

	--TODO: make it so init_seed_objs can be called after super.init?
	--right now it doens't work because super.init pushes to the state stack, which isn't updated by init_seed_objs
	--maybe change the representation back to pushing before step and not after?
	self:init_seed_objs()
	self.super.init(self)

	console.ENV.find_player = self.find_player

	self.prev_obj_count=0
	self.modify_loading_jank=false
	self.first_level=self:level_index()
	self.loading_jank_offset=#pico8.cart.objects+1

	self.modify_rng_seeds=false
	self.rng_seed_idx = -1

	self.full_game_playback = false

	self:state_changed()
end

function cctas:toggle_key(i ,frame)
	-- don't allow changing the inputs while the player is dead
	-- TODO: also do this for hold
	if not self.inputs_active then
		return
	end
	self.super.toggle_key(self, i, frame)
end

function cctas:keypressed(key, isrepeat)
	if self.full_game_playback then
		self.full_game_playback = false
		self.realtime_playback = false
	elseif self.realtime_playback then
		self.super.keypressed(self,key,isrepeat)
	elseif self.modify_loading_jank then
		self:loading_jank_keypress(key,isrepeat)
	elseif self.modify_rng_seeds then
		self:rng_seed_keypress(key,isrepeat)
	elseif key=='a' and not isrepeat then
		self.modify_loading_jank = true
		self:full_rewind()
	elseif key=='b' and not isrepeat then
		self.rng_seed_idx = -1
		-- don't enable rng mode if no seedable objects exist
		if self:advance_seeded_obj(1) then
			self.modify_rng_seeds = true
		end
	elseif key=='f' then
		--TODO: undoable? what about other ops (loading jank)
		self:next_level()
	elseif key=='s' then
		self:prev_level()
	elseif key=='d' and love.keyboard.isDown('lshift', 'rshift') then
		self:player_rewind()
	elseif key == 'n' and love.keyboard.isDown('lshift', 'rshift') then
		self:begin_full_game_playback()
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

function cctas:rng_seed_keypress(key,isrepeat)
	-- TODO: make seed visually update in the current frame, and make rewinding not visually broken
	if key=='up' or key == 'down' then
		local obj = pico8.cart.objects[self.rng_seed_idx]
		for type, seed in pairs(vanilla_seeds) do
			if pico8.cart[type] ~= nil and
			   pico8.cart[type] == obj.type then
				if key=='up' then
					seed.increase_seed(obj)
				else
					seed.decrease_seed(obj)
				end
				for state in self:state_iter() do
					for _, pobj in ipairs(state.cart.objects) do
						if pobj.__tas_id == obj.__tas_id then
							seed.set_seed(pobj, obj.__tas_seed)
						end
					end
				end
				-- self:rewind()
				-- self:step()
			end
		end
	elseif key == 'right' then
		self:advance_seeded_obj(1)
	elseif key == 'left' then
		self:advance_seeded_obj(-1)
	elseif key == 'b' and not isrepeat then
		self.modify_rng_seeds = false
	end
end

-- cycle the rng seed index forward if dir is 1 and backward if it is -1
-- returns true if a seedable object exists
function cctas:advance_seeded_obj(dir)
	local i = self.rng_seed_idx == -1 and #pico8.cart.objects or self.rng_seed_idx
	local start = i
	repeat
		-- advance i by 1 cyclically (darn 1-indexed lua...)
		i = (i + dir - 1) % #pico8.cart.objects + 1
		local obj = pico8.cart.objects[i]
		for type, seed in pairs(vanilla_seeds) do
			if pico8.cart[type] ~= nil and
				pico8.cart[type] == obj.type then
				self.rng_seed_idx = i
				return true
			end
		end
	until i == start
	return false
end

function cctas:begin_full_game_playback()
	api.reload()
	api.run()
	pico8.cart.begin_game()
	pico8.cart._draw()

	self:init_seed_objs()
	self:clearstates()
	self:load_input_file()

	self.realtime_playback = true
	self.full_game_playback = true

end
--TODO: rename this
function cctas:reset_vars()
	self.hold=0
end

local function load_room_wrap(idx)
	--TODO: support evercore style carts
	pico8.cart.load_room(idx%8, math.floor(idx/8))
end

-- if reset changes is false, loading jank and rng seeds will not be touched
-- otherwise, they will be reset
function cctas:load_level(idx, reset_changes)
	local seeds = self:get_rng_seeds()
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
	if reset_changes then
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

	self:init_seed_objs()
	self:clearstates()
	self:reset_vars()

	if not reset_changes then
		self:load_rng_seeds(seeds)
	end

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

function cctas:pushstate()
	if self.level_time>0 or self:find_player() then
		self.level_time = self.level_time + 1
	end
	self.super.pushstate(self)
end

function cctas:popstate()
	if self.level_time>0 then
		self.level_time = self.level_time-1
	end
	self.super.popstate(self)
end

function cctas:step()
	local lvl_idx=self:level_index()
	self.super.step(self)

	if lvl_idx~=self:level_index() then
		if self.full_game_playback then
			print(("%02d:%02d.%03d (%d)"):format(pico8.cart.minutes, pico8.cart.seconds, pico8.cart.frames/30*1000, self.level_time-1))
			--TODO: if the input file could not be loaded, reset the inputs
			self:init_seed_objs()
			self:clearstates()
			self:load_input_file()
		else
			-- TODO: make it so clouds don't jump??
			self:full_rewind()
		end
		return
	end

	self:state_changed()
end

function cctas:rewind()
	self.super.rewind(self)
	self:state_changed()
end

function cctas:full_rewind()
	self.super.full_rewind(self)

	self:state_changed()
	self:reset_vars()
end

function cctas:full_reset()
	self.super.full_reset(self)

	self:reset_vars()
	self:init_seed_objs()
	self:state_changed()
end

function cctas:player_rewind()
	if self.level_time>0 or self.inputs_active then
		for _ = 1, self.level_time do
			self:popstate()
		end
		self:loadstate()
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
	self.level_time = 0

	self:state_changed()
end

function cctas:frame_count()
	return self.level_time
end

function cctas:state_changed()
	self.inputs_active=self:predict(self.find_player,1)
end

function cctas:get_editor_state()
	--TODO: seeds
	local s = self.super.get_editor_state(self)
	s.prev_obj_count = self.prev_obj_count
	s.loading_jank_offset=self.loading_jank_offset
	s.level_time = self.level_time
	return s
end

function cctas:load_editor_state(state)
	self.super.load_editor_state(self,state)
	self.prev_obj_count = state.prev_obj_count
	self.loading_jank_offset=state.loading_jank_offset
	self.level_time = state.level_time
end


--loads rng seeds for the current state
--should (probably be called when there's no states pushed state)
--TODO: consider whether this should affect all states (probably yes?)
function cctas:init_seed_objs()
	for _, obj in ipairs(pico8.cart.objects) do
		obj.__tas_id = {}
		for type, seed in pairs(vanilla_seeds) do
			if pico8.cart[type] ~= nil and
			   pico8.cart[type] == obj.type then
					seed.init(obj)
			end
		end
	end
end

function cctas:get_rng_seeds()

	local seeds = {}
	local initial_state = self:state_iter()()
	for _, obj in ipairs(initial_state.cart.objects) do
		if obj.__tas_seed then
			table.insert(seeds, obj.__tas_seed)
		end
	end
	return seeds
end

-- loads the seed for the current frame and its copy in the state stack
-- seeds not given will not be left at the default value
-- TODO: change repr so it only needs to be done for one of them?
--
function cctas:load_rng_seeds(t)
	local i=1
	for _, obj in ipairs(pico8.cart.objects) do
		if i > #t then
			break
		end
		for type, seed in pairs(vanilla_seeds) do
			if pico8.cart[type] ~= nil and
			   pico8.cart[type] == obj.type then
				seed.set_seed(obj, t[i])
				i = i+1
				break
			end
		end
	end

	--hacky way to sync with the stack
	self:popstate()
	self:pushstate()
end

function cctas:get_input_file_obj()
	local stripped_cartname = cartname:match("[^.]+")
	local dirname = stripped_cartname
	if not love.filesystem.getInfo(dirname, "directory") then
		if not love.filesystem.createDirectory(dirname) then
			print("error creating save directory")
			return nil
		end
	end

	local filename = ("%s/TAS%d.tas"):format(dirname, self:level_index()+1)
	return love.filesystem.newFile(filename)
end

function cctas:get_input_str(i,j)
	--only include the seeds in the string for a full level input
	if i ~= nil then
		return self.super.get_input_str(self,i,j)
	end
	return ("[%s]%s"):format(table.concat(self:get_rng_seeds(),","),self.super.get_input_str(self))
end

function cctas:load_input_str(str, i)
	local seeds,inputs = str:match("%[([^%]]*)%](.*)")
	if not seeds then -- try loading without rng seeds
		return self.super.load_input_str(self, str, i)
	elseif not inputs then
		print("invalid input file")
		return false
	end

	local seeds_tbl={}

	for seed in seeds:gmatch("[^,]+") do
		if tonumber(seed) == nil then
			print("invalid input file")
			return false
		else
			table.insert(seeds_tbl, tonumber(seed))
		end
	end

	if not self.super.load_input_str(self, inputs, i) then
		return false
	end
	self:load_rng_seeds(seeds_tbl)
	return true
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
				setPicoColor(6)
				love.graphics.rectangle('line', obj.x-1, obj.y-1, 10,10)
			end
		end
		love.graphics.pop()

		love.graphics.setColor(1,1,1)
		love.graphics.printf(('loading jank offset: %+d'):format(self.loading_jank_offset),1,100,48,"left",0,2/3,2/3)
	elseif self.modify_rng_seeds then
		love.graphics.push()
		love.graphics.translate(self.hud_w,self.hud_h)

		local obj = pico8.cart.objects[self.rng_seed_idx]
		for type, seed in pairs(vanilla_seeds) do
			if pico8.cart[type] ~= nil and
				pico8.cart[type] == obj.type then
				seed.draw(obj)
			end
		end
		love.graphics.pop()

		love.graphics.setColor(1,1,1)
		love.graphics.print("rng manip mode",1,100,0,2/3,2/3)
	end

end

return cctas

