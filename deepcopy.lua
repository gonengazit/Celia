function deepcopy(orig, seen, upvalues)
    seen = seen or {}
    upvalues = upvalues or {}
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
            rawset(ret,deepcopy(k,seen,upvalues),deepcopy(v,seen,upvalues))
        end
        setmetatable(ret, deepcopy(getmetatable(orig), seen, upvalues))
        return ret

    elseif type(orig)=="function" then
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
        return orig
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

--deepcopy everything, except for api functions
function deepcopy_no_api(v)
    local api_funcs={}
    get_api_funcs(_G, api_funcs)
    return deepcopy(v, api_funcs)
end
