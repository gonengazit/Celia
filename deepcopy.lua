local love11_4,table_new = pcall(require, "table.new")
if not love11_4 then
    --LOVE 11.3 compatibility hack
    table_new=function() return {} end
end

local handle_funcs = {
    ["nil"] = function(orig) return orig end,
    number = function(orig) return orig end,
    string = function(orig) return orig end,
    boolean = function(orig) return orig end,
    table = function(orig,seen,upvalues)
        local see=seen[orig]
        if see then
            return see
        end
        local ret=table_new(#orig,0)
        seen[orig]=ret
        for k,v in pairs(orig) do
            if k == "__tas_id" then
                ret[k]=v
            else
                rawset(ret,deepcopy(k,seen,upvalues),deepcopy(v,seen,upvalues))
            end
        end
        setmetatable(ret, deepcopy(getmetatable(orig), seen, upvalues))
        return ret
    end,
    ["function"] = function(orig,seen,upvalues)
        local see=seen[orig]
        if see then
            return see
        end
        local ret = loadstring(string.dump(orig))
        seen[orig] = ret
        -- there are at most 255 upvalues
        setfenv(ret,deepcopy(getfenv(orig),seen,upvalues))
        for i=1,255 do
            local name,val= debug.getupvalue(orig,i)
            if name == nil then
                break
            end

            debug.setupvalue(ret,i,deepcopy(val,seen,upvalues))
            -- TODO: make this web compatible and/or figure out what this even
            --       does
            if love.system.getOS()~='Web' then
                local uid = debug.upvalueid(orig, i)
                if upvalues[uid] then
                    local other_func, other_i = unpack(upvalues[uid])
                    debug.upvaluejoin(ret, i , other_func, other_i)
                else
                    upvalues[uid] = {ret, i}
                end
            end
        end
        return ret
    end,
    userdata = function(orig,seen)
        local see=seen[orig]
        if see then
            return see
        end
        if getmetatable(orig).type and orig:type()=="Canvas" then
            local ret=love.graphics.newCanvas(orig:getDimensions())
            ret:renderTo(function()
                love.graphics.setShader()
                love.graphics.origin()
                love.graphics.setScissor()
                love.graphics.setColor(1,1,1)
                love.graphics.draw(orig, 0, 0)
            end)
            seen[orig]=ret
            return ret
        else
            seen[orig]=orig
            return orig
        end
    end
}
local err_function = function (orig) error(("can't copy type %q"):format(type(orig))) end
function deepcopy(orig, seen, upvalues)
    return (handle_funcs[type(orig) or err_function]) (orig,seen or {}, upvalues or {})



end

local function deepcopy_debug(orig, seen, upvalues, path)
    --path is used for debugging purposes
    --can delete it to improve performance

    seen = seen or {}
    upvalues = upvalues or {}
    path = path or {}

    if seen[orig] then
        return seen[orig]
    end
    if type(orig) == "nil" or type(orig) == "number" or
       type(orig) == "string" or type(orig) == "boolean" then
        return orig
    elseif type(orig)=="table" then
        print(table.concat(path,"."))
        local ret={}
        seen[orig]=ret
        for k,v in pairs(orig) do
            -- print(k)
            -- print(deepcopy(v,seen,upvalues))
            if k == "__tas_id" then
                ret[k]=v
            else
                table.insert(path,k)
                rawset(ret,deepcopy_debug(k,seen,upvalues,{"key "..tostring(k)}),deepcopy_debug(v,seen,upvalues,path))
                table.remove(path)
            end
        end
        setmetatable(ret, deepcopy_debug(getmetatable(orig), seen, upvalues))
        return ret

    elseif type(orig)=="function" then
        print(table.concat(path,"."))
        local ret = loadstring(string.dump(orig))
        seen[orig] = ret
        -- there are at most 255 upvalues
        table.insert(path,"_ENV")
        setfenv(ret,deepcopy_debug(getfenv(orig),seen,upvalues,path))
        table.remove(path)
        for i=1,255 do
            local name,val= debug.getupvalue(orig,i)
            if name == nil then
                break
            end

            table.insert(path,"up_"..tostring(name))
            debug.setupvalue(ret,i,deepcopy_debug(val,seen,upvalues,path))
            table.remove(path)
            local uid = debug.upvalueid(orig, i)
            if upvalues[uid] then
                local other_func, other_i = unpack(upvalues[uid])
                debug.upvaluejoin(ret, i , other_func, other_i)
            else
                upvalues[uid] = {ret, i}
            end

        end
        return ret
    elseif type(orig)=="userdata" then
        print(table.concat(path,"."))
        if getmetatable(orig).type and orig:type()=="Canvas" then
            local ret=love.graphics.newCanvas(orig:getDimensions())
            ret:renderTo(function()
                love.graphics.setShader()
                love.graphics.origin()
                love.graphics.setScissor()
                love.graphics.setColor(1,1,1)
                love.graphics.draw(orig, 0, 0)
            end)
            return ret
        else
            return orig
        end
    else
        error(("can't copy type %q"):format(type(orig)))
    end
end

function deepcopy_no_api(orig)
    local nocopy = {[_G]=_G}
    for _,v in pairs(new_sandbox()) do
        nocopy[v]=v
    end
    local ret={}
    local upvalues={}
    for k,v in pairs(orig) do
        -- don't copy sfx or rom, because (currently) they are immutaable
        -- sfx might still be an issue, but a small one
        if k=='sfx' or k=='rom' then
            ret[k]=v
            nocopy[v]=v
        else
            ret[k]=deepcopy(orig[k],nocopy,upvalues)
        end
    end
    return ret
end
function deepcopy_benchmark(v)
    local nocopy = {}
    for _,v in pairs(new_sandbox()) do
        nocopy[v]=v
    end
    nocopy[_G]=_G
    -- nocopy[pico8.sfx]=pico8.sfx


    local t=love.timer.getTime()
    local ret={}
    local times={}
    for k,_ in pairs(v) do
        local t=love.timer.getTime()
        ret[k]= deepcopy(v[k], nocopy)
        -- print(k.." "..love.timer.getTime()-t)
        table.insert(times,{love.timer.getTime()-t,k})
    end
    table.sort(times,function(a,b) return a[1]<b[1] end)
    local s=0
    local total=love.timer.getTime()-t
    for k,v in ipairs(times) do
        print(v[1].." "..v[2])
        s=s+v[1]

    end
    print("total ".. total .." "..s)
    print()
    return ret
end
