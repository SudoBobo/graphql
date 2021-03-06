--- Module for convertion GraphQL query to Avro schema.
---
--- Random notes:
---
--- * The best way to use this module is to just call `avro_schema` method on
---   compiled query object.

local json = require('json')
local path = "graphql.core"
local introspection = require(path .. '.introspection')
local query_util = require(path .. '.query_util')

-- module functions
local query_to_avro = {}

-- forward declaration
local object_to_avro

local gql_scalar_to_avro_index = {
    String = "string",
    Int = "int",
    Long = "long",
    -- GraphQL Float is double precision according to graphql.org.
    -- More info http://graphql.org/learn/schema/#scalar-types
    Float = "double",
    Boolean = "boolean"
}
local function gql_scalar_to_avro(fieldType)
    assert(fieldType.__type == "Scalar", "GraphQL scalar field expected")
    assert(fieldType.name ~= "Map", "Map type is not supported")
    local result = gql_scalar_to_avro_index[fieldType.name]
    assert(result ~= nil, "Unexpected scalar type: " .. fieldType.name)
    return result
end

--- The function converts avro type to the corresponding nullable type in
--- place and returns the result.
---
--- We make changes in place in case of table input (`avro`) because of
--- performance reasons, but we returns the result because an input (`avro`)
--- can be a string. Strings in Lua are immutable.
---
--- In the current tarantool/avro-schema implementation we simply add '*' to
--- the end of a type name.
---
--- If the type is already nullable the function leaves it as if
--- `opts.raise_on_nullable` is false or omitted. If `opts.raise_on_nullable`
--- is true the function will raise an error.
---
--- @tparam table avro avro schema node to be converted to nullable one
---
--- @tparam[opt] table opts the following options:
---
--- * `raise_on_nullable` (boolean) raise an error on nullable type
---
--- @result `result` (string or table) nullable avro type
local function make_avro_type_nullable(avro, opts)
    assert(avro ~= nil, "avro must not be nil")
    local opts = opts or {}
    assert(type(opts) == 'table',
        'opts must be nil or a table, got ' .. type(opts))
    local raise_on_nullable = opts.raise_on_nullable or false
    assert(type(raise_on_nullable) == 'boolean',
        'opts.raise_on_nullable must be nil or a boolean, got ' ..
        type(raise_on_nullable))

    local value_type = type(avro)

    if value_type == "string" then
        local is_nullable = avro:endswith("*")
        if raise_on_nullable and is_nullable then
            error('expected non-null type, got the nullable one: ' ..
                json.encode(avro))
        end
        return is_nullable and avro or (avro .. '*')
    elseif value_type == "table" then
        return make_avro_type_nullable(avro.type, opts)
    end

    error("avro should be a string or a table, got " .. value_type)
end

--- Convert GraphQL type to avro-schema with selecting fields.
---
--- @tparam table fieldType GraphQL type
---
--- @tparam table subSelections fields to select from resulting avro-schema
--- (internal graphql-lua format)
---
--- @tparam table context current traversal context, here it just falls to the
--- called functions (internal graphql-lua format)
---
--- @tresult table `result` is the resulting avro-schema
local function gql_type_to_avro(fieldType, subSelections, context)
    local fieldTypeName = fieldType.__type
    local isNonNull = false

    -- In case the field is NonNull, the real type is in ofType attribute.
    while fieldTypeName == 'NonNull' do
        fieldType = fieldType.ofType
        fieldTypeName = fieldType.__type
        isNonNull = true
    end

    local result

    if fieldTypeName == 'List' then
        local innerType = fieldType.ofType
        local innerTypeAvro = gql_type_to_avro(innerType, subSelections,
            context)
        result = {
            type = "array",
            items = innerTypeAvro,
        }
    elseif fieldTypeName == 'Scalar' then
        result = gql_scalar_to_avro(fieldType)
    elseif fieldTypeName == 'Object' then
        result = object_to_avro(fieldType, subSelections, context)
    elseif fieldTypeName == 'Interface' or fieldTypeName == 'Union' then
        error('Interfaces and Unions are not supported yet')
    else
        error(string.format('Unknown type "%s"', tostring(fieldTypeName)))
    end

    if not isNonNull then
        result = make_avro_type_nullable(result, {raise_on_nullable = true})
    end
    return result
end

--- The function converts a single Object field to avro format.
local function field_to_avro(object_type, fields, context)
    local firstField = fields[1]
    assert(#fields == 1, "The aliases are not considered yet")
    local fieldName = firstField.name.value
    local fieldType = introspection.fieldMap[fieldName] or
        object_type.fields[fieldName]
    assert(fieldType ~= nil)
    local subSelections = query_util.mergeSelectionSets(fields)

    local fieldTypeAvro = gql_type_to_avro(fieldType.kind, subSelections,
        context)
    return {
        name = fieldName,
        type = fieldTypeAvro,
    }
end

--- Convert GraphQL object to avro record.
---
--- @tparam table object_type GraphQL type object to be converted to Avro schema
---
--- @tparam table selections GraphQL representations of fields which should be
--- in the output of the query
---
--- @tparam table context additional information for Avro schema generation; one
--- of the fields is `namespace_parts` -- table of names of records from the
--- root to the current object
---
--- @treturn table `result` is the corresponding Avro schema
object_to_avro = function(object_type, selections, context)
    local groupedFieldSet = query_util.collectFields(object_type, selections,
        {}, {}, context)
    local result = {
        type = 'record',
        name = object_type.name,
        fields = {}
    }
    if #context.namespace_parts ~= 0 then
        result.namespace = table.concat(context.namespace_parts, ".")
    end
    table.insert(context.namespace_parts, result.name)
    for _, fields in pairs(groupedFieldSet) do
        local avro_field = field_to_avro(object_type, fields, context)
        table.insert(result.fields, avro_field)
    end
    context.namespace_parts[#context.namespace_parts] = nil
    return result
end

--- Create an Avro schema for a given query.
---
--- @tparam table query object which avro schema should be created for
---
--- @treturn table `avro_schema` avro schema for any `query:execute()` result
function query_to_avro.convert(query)
    assert(type(query) == "table",
        ('query should be a table, got: %s; ' ..
        'hint: use ":" instead of "."'):format(type(table)))
    local state = query.state
    local context = query_util.buildContext(state.schema, query.ast, {}, {},
        query.operation_name)
    -- The variable is necessary to avoid fullname interferention.
    -- Each nested Avro record creates it's namespace.
    context.namespace_parts = {}
    local rootType = state.schema[context.operation.operation]
    local selections = context.operation.selectionSet.selections
    return object_to_avro(rootType, selections, context)
end

return query_to_avro
