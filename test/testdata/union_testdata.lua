local json = require('json')
local yaml = require('yaml')
local utils = require('graphql.utils')

local union_testdata = {}

local function print_and_return(...)
    print(...)
    return table.concat({ ... }, ' ') .. '\n'
end

function union_testdata.get_test_metadata()
    local schemas = json.decode([[{
        "hero": {
            "name": "hero",
            "type": "record",
            "fields": [
                { "name": "hero_id", "type": "string" },
                { "name": "hero_type", "type" : "string" }
            ]
        },
        "human": {
            "name": "human",
            "type": "record",
            "fields": [
                { "name": "hero_id", "type": "string" },
                { "name": "name", "type": "string" },
                { "name": "episode", "type": "string"}
            ]
        },
        "starship": {
            "name": "starship",
            "type": "record",
            "fields": [
                { "name": "hero_id", "type": "string" },
                { "name": "model", "type": "string" },
                { "name": "episode", "type": "string"}

            ]
        },
        "hero_info": {
            "name": "hero_info",
            "type": "record",
            "fields": [
                { "name": "hero_id", "type": "string" }
            ]
        }
    }]])

    local collections = json.decode([[{
        "hero_collection": {
            "schema_name": "hero",
            "connections": [
                {
                    "name": "hero_connection",
                    "type": "1:1",
                    "variants": [
                        {
                            "determinant": {"hero_type": "human"},
                            "destination_collection": "human_collection",
                            "parts": [
                                {
                                    "source_field": "hero_id",
                                    "destination_field": "hero_id"
                                }
                            ],
                            "index_name": "human_id_index"
                        },
                        {
                            "determinant": {"hero_type": "starship"},
                            "destination_collection": "starship_collection",
                            "parts": [
                                {
                                    "source_field": "hero_id",
                                    "destination_field": "hero_id"
                                }
                            ],
                            "index_name": "starship_id_index"
                        }
                    ]
                },
                {
                    "type": "1:1",
                    "name": "hero_info_connection",
                    "destination_collection":  "hero_info_collection",
                    "parts": [
                        { "source_field": "hero_id", "destination_field": "hero_id" }
                    ],
                    "index_name": "hero_info_id_index"
                }
            ]
        },
        "human_collection": {
            "schema_name": "human",
            "connections": []
        },
        "starship_collection": {
            "schema_name": "starship",
            "connections": []
        },
        "hero_info_collection": {
            "schema_name": "hero_info",
            "connections": []
        }
    }]])

    local service_fields = {
        hero = {
            { name = 'expires_on', type = 'long', default = 0 },
        },
        human = {
            { name = 'expires_on', type = 'long', default = 0 },
        },
        starship = {
            { name = 'expires_on', type = 'long', default = 0 },
        },
        hero_info = {
            { name = 'expires_on', type = 'long', default = 0 },
        }
    }

    local indexes = {
        hero_collection = {
            hero_id_index = {
                service_fields = {},
                fields = { 'hero_id' },
                index_type = 'tree',
                unique = true,
                primary = true,
            },
        },

        human_collection = {
            human_id_index = {
                service_fields = {},
                fields = { 'hero_id' },
                index_type = 'tree',
                unique = true,
                primary = true,
            },
        },

        starship_collection = {
            starship_id_index = {
                service_fields = {},
                fields = { 'hero_id' },
                index_type = 'tree',
                unique = true,
                primary = true,
            },
        },

        hero_info_collection = {
            hero_info_id_index = {
                service_fields = {},
                fields = { 'hero_id' },
                index_type = 'tree',
                unique = true,
                primary = true,
            },
        }
    }

    return {
        schemas = schemas,
        collections = collections,
        service_fields = service_fields,
        indexes = indexes,
    }
end

function union_testdata.init_spaces()
    -- user_collection fields
    local U_USER_ID_FN = 2

    box.once('test_space_init_spaces', function()
        box.schema.create_space('hero_collection')
        box.space.hero_collection:create_index('hero_id_index',
        { type = 'tree', unique = true, parts = { U_USER_ID_FN, 'string' }}
        )

        box.schema.create_space('human_collection')
        box.space.human_collection:create_index('human_id_index',
        { type = 'tree', unique = true, parts = { U_USER_ID_FN, 'string' }}
        )

        box.schema.create_space('starship_collection')
        box.space.starship_collection:create_index('starship_id_index',
        { type = 'tree', unique = true, parts = { U_USER_ID_FN, 'string' }}
        )

        box.schema.create_space('hero_info_collection')
        box.space.hero_info_collection:create_index('hero_info_id_index',
        { type = 'tree', unique = true, parts = { U_USER_ID_FN, 'string' }}
        )
    end)
end

function union_testdata.fill_test_data(shard)
    local shard = shard or box.space

    shard.hero_collection:replace(
    { 1827767717, 'hero_id_1', 'human'})
    shard.hero_collection:replace(
    { 1827767717, 'hero_id_2', 'starship'})

    shard.human_collection:replace(
    { 1827767717, 'hero_id_1', 'Luke', "EMPR"})

    shard.starship_collection:replace(
    { 1827767717, 'hero_id_2', 'Falcon-42', "NEW"})

    shard.hero_info_collection:replace(
    { 1827767717, 'hero_id_1'})

    shard.hero_info_collection:replace(
    { 1827767717, 'hero_id_2'})
end

function union_testdata.drop_spaces()
    box.space._schema:delete('oncetest_space_init_spaces')
    box.space.human_collection:drop()
    box.space.starship_collection:drop()
    box.space.hero_collection:drop()
end

function union_testdata.run_queries(gql_wrapper)
    local results = ''



    --local query = [[
    --    query obtainHeroes($hero_id: String) {
    --        hero_collection(hero_id: $hero_id) {
    --            hero_id
    --            hero_type
    --
    --
    --            hero_connection(hero_id: $hero_id){
    --                hero_id
    --            }
    --        }
    --    }
    --]]

    --local query = [[
    --    query obtainOrganizationUsers($hero_id: String) {
    --        hero_collection(hero_id: $hero_id) {
    --            ... on human {
    --                name
    --            }
    --            ... on starship {
    --                model
    --            }
    --        }
    --    }
    --]]

    local query = [[
        query obtainHeroes($hero_id: String) {
            hero_collection(hero_id: $hero_id) {
                hero_id
                hero_type
                hero_connection {

                    ... on human_collection {
                        name
                    }

                    ... on starship_collection {
                        model
                    }
                }
            }
        }
    ]]

    utils.show_trace(function()
        local variables_1 = {hero_id = 'hero_id_1'}
        local gql_query_1 = gql_wrapper:compile(query)
        local result = gql_query_1:execute(variables_1)
        results = results .. print_and_return(
        ('RESULT\n%s'):format(yaml.encode(result)))
    end)

    --utils.show_trace(function()
    --    local variables_2 = {hero_id = 'hero_id_2'}
    --    local gql_query_2 = gql_wrapper:compile(query)
    --    local result = gql_query_2:execute(variables_2)
    --    results = results .. print_and_return(
    --    ('RESULT\n%s'):format(yaml.encode(result)))
    --end)

    return results
end

return union_testdata
