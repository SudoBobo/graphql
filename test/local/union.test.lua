#!/usr/bin/env tarantool

local fio = require('fio')

-- require in-repo version of graphql/ sources despite current working directory
package.path = fio.abspath(debug.getinfo(1).source:match("@?(.*/)"):
    gsub('/./', '/'):gsub('/+$', '')) .. '/../../?.lua' .. ';' .. package.path

local json = require('json')
local yaml = require('yaml')
local graphql = require('graphql')
local utils = require('graphql.utils')

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
            { "name": "human_id", "type": "string" },
            { "name": "name", "type": "string" }
        ]
    },
    "starship": {
        "name": "starship",
        "type": "record",
        "fields": [
            { "name": "starship_id", "type": "string" },
            { "name": "model", "type": "string" }
        ]
    }
}]])

local collections = json.decode([[{
    "episode_collection": {
        "schema_name": "episode",
        "connections": [
            {
                name = 'hero_connection',
                variants = [
                    {
                        filter = {type = 'human'},
                        destination_collection = 'human_collection',
                        parts = [
                            {
                                source_field = 'hero_id',
                                destination_field = 'human_id'
                            }
                        ]
                    },
                    {
                        filter = {type = 'starship'},
                        destination_collection = 'starship_collection',
                        parts = [
                            {
                                source_field = 'field_name_source_1',
                                destination_field = 'field_name_destination_1'
                            }
                        ]
                    }
                ]
            }
        ]
    },
    "human_collection": {
        "schema_name": "human"
    },
    "starship_collection": {
        "schema_name": "starship"
    }
}]])

local query_1 = [[
    query obtainOrganizationUsers($hero_id: String) {
        hero_collection(hero_id: $hero_id) {
            ... on human {
                name
            }
            ... on starship {
                model
            }
        }
    }
]]

utils.show_trace(function()
    local variables_1 = {organization_id = 'ghi'}
    local gql_query_1 = gql_wrapper:compile(query_1)
    local result = gql_query_1:execute(variables_1)
    print(('RESULT\n%s'):format(yaml.encode(result)))
end)
