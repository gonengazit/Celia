local bit = require("bit")
local consts=require("fix32_constants")
local api=require("api")
local exponent=2^16
local max32=2^32
local mask=exponent-1
local inf=0x7fffffff/exponent
local neginf=bit.tobit(0x80000001)/exponent


local function fix32_add(a,b)
	return bit.tobit(a*exponent + b*exponent)/exponent
end

local function fix32_sub(a,b)
	return bit.tobit(a*exponent - b*exponent)/exponent
end

local function fix32_mul(a,b)
	--use 64 bit integers
	return bit.tobit(bit.rshift((a*exponent* 1LL) * (b * exponent * 1LL),16))/exponent
end

local function trunc(x)
	return x>=0 and math.floor(x) or math.ceil(x)
end

local function fix32_div(a,b)
	a=a*exponent
	b=b*exponent

	if b==0 then
		return a>=0 and inf or neginf
	elseif b>=0 and bit.band(b,0xffff)==0 then
		-- b is an integer. no overflow can occur.
		return bit.tobit(trunc(a/(bit.rshift(b,16))))/exponent
	end

	local val = trunc(a*exponent / b)
	if val<=-0x80000000 then
		return neginf
	elseif val>0x7fffffff then
		return inf
	end
	return val/exponent
end

local function fix32_unm(a)
	return bit.tobit(-a*exponent)/exponent
end

local function fix32_bnot(a)
	return bit.bnot(a*exponent)/exponent
end

local function fix32_bor(a,b)
	return bit.bor(a*exponent, b*exponent)/exponent
end

local function fix32_band(a,b)
	return bit.band(a*exponent, b*exponent)/exponent
end

local function fix32_bxor(a,b)
	return bit.bxor(a*exponent, b*exponent)/exponent
end

local function fix32_tostr(a)
	a=a*exponent
	return string.format("0x%04x.%04x",bit.rshift(bit.band(a,0xffff0000),16), bit.band(a,0xffff))
end

local function fix32_abs(a)
	return a==-0x8000.0000 and 0x7fff.ffff or
		     a>=0 and a or fix32_unm(a)
end

local function fix32_mod(a,b)
	a=a*exponent
	b=fix32_abs(b)*exponent
	if b==0 then
		return 0
	else
		return (a%b)/exponent
	end
end


local function fix32_sqrt(a)
	-- uses this algorithm https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Binary_numeral_system_(base_2)
	-- (same as pico8)
	--
	--the result is sqrt(a)=sqrt(a*exponent^2)/exponent
	--
	--a*exponent^2 is 2^48, which still fits within lossless double precision

	local a=a*exponent^2
	if(a<0) then
		return 0
	end

	local pow2=2^24
	local res=0

	while pow2>=1 do
		if (res+pow2)^2<=a then
			res=res+pow2
		end
		pow2=pow2/2
	end
	return res/exponent
end

local function fix32_pow(a,b)
	if b==0 then
		return 1
	end

	-- a^(b) = (1/a)^(-b)
	if b<0 then
		b=-b
		a=fix32_div(1,a)
	end

	--divide b into integer and fractional parts
	local int_b=math.floor(b)
	local frac_b=b-int_b

	-- fractional powers of negatives are (usually) not defined
	if a<0 and frac_b>0 then
		return 0
	end

	local res=1

	--standard integer exponentitation
	local an=a
	while(int_b>=1) do
		if int_b%2~=0 then
			res=fix32_mul(res,an)
		end
		int_b = bit.rshift(int_b,1)
		an=fix32_mul(an,an)
	end

	while frac_b~=0 do
		while frac_b<1 do
			a=fix32_sqrt(a)
			frac_b=frac_b*2
		end

		frac_b=frac_b-1
		res=fix32_mul(res,a)
	end
end

local function fix32_from_int(a)
	--convert a 32 bit int to a 16.16 value
	return bit.tobit(a)/exponent
end

local function str_to_fix32_str(s)
	-- receives a string of a number
	-- returns a string that will be parsed as the exact 16.16 number by the lua parser
	--

	local dotidx=string.find(s,"%.") or #s+1

	--string representation of the exact value
	local numstr
	if s:match("[xX]") then
		--only take 4 digits before and after the point
		local radixidx=string.find(s, "[xX]")
		numstr= s:sub(1,radixidx)..s:sub(math.max(dotidx-4,radixidx+1),dotidx+4)
	elseif s:match("[bB]") then
		--similarly to hex, only take 16 digits before and after the point
		local radixidx=string.find(s, "[bB]")
		numstr= s:sub(1,radixidx)..s:sub(math.max(dotidx-16,radixidx+1),dotidx+16)
	else
		numstr=s
	end

	--return a string that will be parsed correctly as this number
	return string.format("%a",bit.tobit(trunc(tonumber(numstr)*exponent))/exponent)
end

local function fix32_tonumber(x)
	if type(x)=="string" then
		return tonumber(str_to_fix32_str(x))
	end
	return tonumber(x)
end

local function fix32_rnd(x)
	if type(x)=="table" then
		return x[math.floor(fix32_rnd(#x)+1)]
	else
		x = (fix32_tonumber(x) or 1) * exponent
		if(x==0) then
			return 0
		end
		x = x % max32
		pico8.rng_high=bit.bor(bit.lshift(pico8.rng_high,16), bit.rshift(pico8.rng_high, 16))
		pico8.rng_high=bit.tobit(pico8.rng_low + pico8.rng_high)
		pico8.rng_low=bit.tobit(pico8.rng_low + pico8.rng_high)
		return bit.tobit(pico8.rng_high % max32 % x)/exponent
	end
end

local function fix32_srand(x)
	x = (fix32_tonumber(x) or 0) * exponent
	if(x==0) then
		pico8.rng_high=0x60009755
		x=0xdeadbeef
	else
		pico8.rng_high=bit.bxor(x, 0xbead29ba)
	end

	for _=1,0x20 do
		pico8.rng_high=bit.bor(bit.lshift(pico8.rng_high,16), bit.rshift(pico8.rng_high, 16))
		pico8.rng_high=bit.tobit(pico8.rng_high + x)
		x = bit.tobit(x + pico8.rng_high)
	end
	pico8.rng_low = x
end

local function fix32_run_ext()
	fix32_srand(love.math.random(max32-1)/exponent)
end




local function fix32_sin(x)
	x=fix32_tonumber(x)*exponent
	local index=bit.band(bit.rshift(x+0x4002,2), 0x3fff)
	if index > 0x1fff then
		index = 0x4000 - index
	end
	if index < 0x1000 then
		return bit.tobit(consts.cos_val[index])/exponent
	end
	return bit.tobit(-consts.cos_val[0x2000-index])/exponent
end

local function fix32_cos(x)
	x=fix32_tonumber(x)*exponent
	local index=bit.band(bit.rshift(x+2,2), 0x3fff)
	if index > 0x1fff then
		index = 0x4000 - index
	end
	if index < 0x1000 then
		return bit.tobit(consts.cos_val[index])/exponent
	end
	return bit.tobit(-consts.cos_val[0x2000-index])/exponent
end

local function fix32_atan2(dx,dy)
	local quot=fix32_div(-dy,dx)
	local sign=api.sgn(quot)
	local abs=fix32_abs(quot)
	quot = quot*exponent
	abs = abs*exponent
	local ret
	if abs<0x10001 then
		ret=sign * consts.atan_val[bit.rshift(abs,5)]
	else
		abs=fix32_abs(fix32_div(dx,-dy))*exponent
		ret = sign * (0x4000 - consts.atan_val[bit.rshift(abs,5)])
	end

	if dx<0 then
		ret = ret + 0x8000
	end
	return bit.band(ret%max32,0xffff)/exponent
end

local function fix32_init()
	fixed_point_enabled = true
	print("fixed point enabled!")
	api.__fix_add=fix32_add
	api.__fix_sub=fix32_sub
	api.__fix_mul=fix32_mul
	api.__fix_div=fix32_div
	api.__fix_mod=fix32_mod
	api.__fix_pow=fix32_pow
	api.__fix_unm=fix32_unm
	api.sqrt=fix32_sqrt

	api._tonumber = fix32_tonumber

	function api.time()
		return fix32_div(pico8.frames,30)
	end
	api.t=api.time

	api.rnd=fix32_rnd
	api.srand=fix32_srand

	api.sin=fix32_sin
	api.cos=fix32_cos
	api.atan2=fix32_atan2

	local api_run=api.run
	function api.run()
		fix32_run_ext()
		api_run()
	end
end
return {
	add=fix32_add,
	sub=fix32_sub,
	mul=fix32_mul,
	div=fix32_div,
	unm=fix32_unm,
	bnot=fix32_bnot,
	bor=fix32_bor,
	band=fix32_band,
	tostr=fix32_tostr,
	abs=fix32_abs,
	mod=fix32_mod,
	sqrt=fix32_sqrt,
	pow=fix32_pow,
	from_int=fix32_from_int,
	str_to_fix32_str= str_to_fix32_str,
	rnd=fix32_rnd,
	srand=fix32_srand,
	run_ext=fix32_run_ext,
	init=fix32_init,
	sin=fix32_sin,
	cos=fix32_cos,
	atan2=fix32_atan2
}






