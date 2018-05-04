local string_format = string.format

local M = {}

local UNSUPPORTED_TYPE = {
    ['table'] = true,
    ['function'] = true,
    ['thread'] = true,
    ['nil'] = true,
}

local meta

local function new_table_field(t,k)
    assert(k)
    assert(not rawget(t._fields,k),k)
    local v = setmetatable({
        _root = t._root,
        _fields = {},
        _key = string_format('%s.%s',t._key,k)
        },meta)
    rawset(t._fields,k,v)
    return v
end

local function get_dirty_fields(t)
    if not t._dirty then
        return nil
    end

    return assert(t._dirty_fields)
end

local function is_dirty(t)
    return t._dirty
end

local function clear_dirty_fields(t)
    t._dirty_fields = {}
    t._dirty = false
end

local function clear_from_array(t)
    assert(t._root ~= t)
    t._fields = {}

    t._root._dirty = true
    t._root._dirty_fields[t._key] = true
end

local function remove_from_array(t,index)
    assert(t._root ~= t)
    local o = table.remove(t._fields,index)
    
    t._root._dirty = true
    t._root._dirty_fields[t._key] = true
    return o    
end

local function delete_from_hash(t,key)
    assert(t._root ~= t)
    rawset(t._fields,key,nil)
    
    t._root._dirty = true
    t._root._dirty_fields[t._key] = true
end

local function deep_copy(t)
    local o = {}
    for k,v in pairs(t._fields) do
        if type(v) == 'table' then
            rawset(o,k,deep_copy(v))
        else
            rawset(o,k,v)
        end
    end
    return o
end

local funcs = {
    new_table_field = new_table_field,
    get_dirty_fields = get_dirty_fields,
    clear_dirty_fields = clear_dirty_fields,
    deep_copy = deep_copy,
    clear_from_array = clear_from_array,
    remove_from_array = remove_from_array,
    delete_from_hash = delete_from_hash,
    is_dirty = is_dirty,
}

local function mt_index(t,k)
    if funcs[k] then
        return funcs[k]
    else
        return rawget(t._fields,k)
    end
end

local function mt_assign(t,k,v)
    local _type = type(v)
    if UNSUPPORTED_TYPE[_type] then
        error(string_format('you can not assign a valud of type(%s) to field(%s)',_type,k))
        return
    end
    
    t._root._dirty = true
    t._root._dirty_fields[string_format('%s.%s',t._key,k)] = true
    rawset(t._fields,k,v)
end

local function mt_len(t)
    return #t._fields
end

local function mt_pairs(t)
    return pairs(t._fields)
end

meta = {
    __index = mt_index,
    __newindex = mt_assign,
    __len = mt_len,
    __pairs = mt_pairs,
}

function M.new(key)
    local data = {
        _dirty = false,
        _fields = {},
        _dirty_fields = {},
        _key = key
    }

    data._root = data
    return setmetatable(data,meta)
end

local function copy_from(dest,src)
    for k,v in pairs(src) do
        local t = type(v)
        if t == 'table' then
            copy_from(dest:new_table_field(k),v)
        elseif t == 'boolean' or 
            t == 'string' or 
            t == 'number' then
            dest[k] = v
        else
            error(string_format('you can not assign a valud of type(%s) to field(%s)',_type,k))
        end
    end
end

function M.new_from(key,src)
    local dest = M.new(key)
    copy_from(dest,src)
    return dest
end

return M