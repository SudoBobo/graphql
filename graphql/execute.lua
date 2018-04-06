local utils = require('graphql.utils')
local core_util = require('graphql.core.util')

-- short name
local check = utils.check

local execute = {}

--- Get graphql-lua object representing operation.
---
--- @tparam table query_ast
--- @tparam string operation_name
---
--- @treturn table `operation`
local function get_operation(query_ast, operation_name)
    -- XXX: make operation name optional in case of an one operation in the
    -- schema, see query_util.buildContext
    check(operation_name, 'operation_name', 'string')

    local operation

    for _, definition in ipairs(query_ast.definitions) do
        if definition.kind == 'operation' then
            if definition.name.value == operation_name then
                operation = definition
            end
        end
    end

    assert(operation ~= nil,
        ('cannot find operation "%s"'):format(operation_name))
    return operation
end

--- XXX
local function get_argument_type(field_type, argument_name)
    for name, argument_type in pairs(field_type.arguments) do
        if name == argument_name then
            return argument_type
        end
    end
    error(('cannot find argument "%s"'):format(argument_name))
end

local function get_argument_values(field_type, selection, variables)
    local args = {}
    for _, argument in ipairs(selection.arguments or {}) do
        local argument_name = argument.name.value
        assert(argument_name ~= nil)
        local argument_type = get_argument_type(field_type, argument_name)
        local value = core_util.coerceValue(argument.value, argument_type,
            variables)
        args[argument_name] = value
    end
    return args
end

local function filter_object(object, object_type, selections, qcontext,
        variables)
    local required_fields = {}
    local selections_per_fields = {}

    -- XXX: allow null for object if object_type is nullable (we should not
    -- skip NonNull below for an element)

    -- XXX: support aliases, fragments, directives
    for _, selection in ipairs(selections) do
        assert(selection.alias == nil, 'NIY: aliases')
        local field_name = selection.name.value
        required_fields[field_name] = true
        selections_per_fields[field_name] = selection
    end

    local filtered_object = {}
    local fields_info = {}

    for field_name, _ in pairs(required_fields) do
        local field_type = object_type.fields[field_name]
        assert(field_type ~= nil)

        if field_type.prepare_resolve then
            -- XXX: attend NonNull somehow
            -- set deduce inner_type and set is_list
            local is_list = false
            local inner_type = field_type.kind
            while inner_type.ofType ~= nil do
                if inner_type.__type == 'List' then
                    is_list = true
                    inner_type = inner_type.ofType
                elseif inner_type.__type == 'NonNull' then
                    inner_type = inner_type.ofType
                else
                    error('unknown __type: ' .. tostring(inner_type.__type))
                end
            end

            local selection = selections_per_fields[field_name]
            local args = get_argument_values(field_type, selection, variables)

            local info = {qcontext = qcontext}
            local prepared_resolve = field_type.prepare_resolve(
                object, args, info)
            fields_info[field_name] = {
                is_list = is_list,
                kind = inner_type,
                prepared_resolve = prepared_resolve,
                selections = selection.selectionSet.selections,
            }
        else
            -- XXX: is call to coerceValue needed here?
            if object[field_name] ~= nil then
                filtered_object[field_name] = object[field_name]
            end
        end
    end

    local prepared_object = {
        filtered_object = filtered_object,
        fields_info = fields_info,
    }
    return prepared_object
end

local function filter_object_list(object_list, object_type, selections,
        qcontext, variables)
    local prepared_object_list = {}

    for _, object in ipairs(object_list) do
        local prepared_object = filter_object(object, object_type, selections,
            qcontext, variables)
        table.insert(prepared_object_list, prepared_object)
    end

    return prepared_object_list
end

local function invoke_resolve(prepared_object, qcontext, variables)
    local open_set = {}

    for field_name, field_info in pairs(prepared_object.fields_info) do
        local object_or_list = field_info.prepared_resolve:invoke()
        local object_type = field_info.kind
        local selections = field_info.selections

        -- XXX: maybe we can always process lists and deduce is_list from
        -- graphql types

        local child
        if field_info.is_list then
            local child_prepared_object_list = filter_object_list(
                object_or_list, object_type, selections, qcontext,
                variables)

            -- construction
            prepared_object.filtered_object[field_name] = {}
            for _, child_prepared_object in
                    ipairs(child_prepared_object_list) do
                table.insert(prepared_object.filtered_object[field_name],
                    child_prepared_object.filtered_object)
            end

            child = {
                prepared_object_list = child_prepared_object_list,
            }
        else
            local child_prepared_object = filter_object(object_or_list,
                object_type, selections, qcontext, variables)

            -- construction
            prepared_object.filtered_object[field_name] =
                child_prepared_object.filtered_object

            child = {
                prepared_object = child_prepared_object,
            }
        end

        table.insert(open_set, child)
    end

    return open_set
end

local function invoke_resolve_list(prepared_object_list, qcontext, variables)
    local open_set = {}

    for _, prepared_object in ipairs(prepared_object_list) do
        local child_open_set = invoke_resolve(prepared_object, qcontext,
            variables)
        utils.expand_list(open_set, child_open_set)
    end

    return open_set
end

--- XXX
function execute.execute(schema, query_ast, variables, operation_name)
    local operation = get_operation(query_ast, operation_name)
    local root_object_type = schema[operation.operation]
    assert(root_object_type ~= nil,
        ('cannot find root type for operation "%s"'):format(operation_name))
    local root_selections = operation.selectionSet.selections

    local qcontext = {}
    local root_object = {}

    local prepared_root_object = filter_object(
        root_object, root_object_type, root_selections, qcontext, variables)
    local filtered_root_object = prepared_root_object.filtered_object
    local open_set = invoke_resolve(prepared_root_object, qcontext, variables)

    -- XXX: don't mix requests to different fields, make all requests for an
    -- one field, the for the next: add requests resort stage

    while true do
        local item = table.remove(open_set, 1)
        if item == nil then break end
        local child_open_set
        if item.prepared_object ~= nil then
            child_open_set = invoke_resolve(item.prepared_object, qcontext,
                variables)
        elseif item.prepared_object_list ~= nil then
            child_open_set = invoke_resolve_list(item.prepared_object_list,
                qcontext, variables)
        else
            assert(false,
                'cannot find prepared_object nor prepared_object_list')
        end

        utils.expand_list(open_set, child_open_set)
    end

    return filtered_root_object
end

return execute
