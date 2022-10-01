function deepcopy(orig, seen, upvalues, path)
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
        local ret={}
        seen[orig]=ret
        for k,v in pairs(orig) do
            -- print(k)
            -- print(deepcopy(v,seen,upvalues))
            table.insert(path,k)
            rawset(ret,deepcopy(k,seen,upvalues,{"key "..tostring(k)}),deepcopy(v,seen,upvalues,path))
            table.remove(path)
        end
        setmetatable(ret, deepcopy(getmetatable(orig), seen, upvalues))
        return ret

    elseif type(orig)=="function" then
        local ret = loadstring(string.dump(orig))
        seen[orig] = ret
        -- there are at most 255 upvalues
        table.insert(path,"_ENV")
        setfenv(ret,deepcopy(getfenv(orig),seen,upvalues,path))
        table.remove(path)
        for i=1,255 do
            local name,val= debug.getupvalue(orig,i)
            if name == nil then
                break
            end

            table.insert(path,"up_"..tostring(i))
            debug.setupvalue(ret,i,deepcopy(val,seen,upvalues))
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
        if getmetatable(orig).type and orig:type()=="Canvas" then
            local ret=love.graphics.newCanvas(orig:getDimensions())
            ret:renderTo(function()
                love.graphics.setShader()
                love.graphics.origin()
                love.graphics.setScissor()
                love.graphics.setColor(255,255,255)
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

local function get_api_funcs(t, seen, visited)
    visited=visited or {}
    if visited[t] then
        return
    end
    visited[t]=true
    if(t==pico8) then
        return
    elseif seen[t] then
        return
    elseif type(t) == "function" then
        seen[t]=t
    elseif type(t) == "table" then
        for k,v in pairs(t) do
            get_api_funcs(v,seen, visited)
        end
    end
end

--deepcopy everything, except for api functions, and _G
function deepcopy_no_api(v)
    local api_funcs={}
    get_api_funcs(_G, api_funcs)
    api_funcs[_G]=_G -- don't copy _G
    return deepcopy(v, api_funcs)
end
