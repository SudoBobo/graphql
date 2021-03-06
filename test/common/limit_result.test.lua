#!/usr/bin/env tarantool
local multirunner = require('multirunner')
local data = require('test_data_user_order')
local test_run = require('test_run').new()
local tap = require('tap')
local graphql = require('graphql')

box.cfg({})
local test = tap.test('result cnt')
test:plan(6)

-- require in-repo version of graphql/ sources despite current working directory
local fio = require('fio')
package.path = fio.abspath(debug.getinfo(1).source:match("@?(.*/)")
    :gsub('/./', '/'):gsub('/+$', '')) .. '/../../?.lua' .. ';' .. package.path

local function run(setup_name, shard)
    print(setup_name)
    local accessor_class
    local virtbox
    -- SHARD
    if shard ~= nil then
        accessor_class = graphql.accessor_shard
        virtbox = shard
    else
        accessor_class = graphql.accessor_space
        virtbox = box.space
    end
    local accessor = accessor_class.new({
        schemas = data.meta.schemas,
        collections = data.meta.collections,
        service_fields = data.meta.service_fields,
        indexes = data.meta.indexes,
        resulting_object_cnt_max = 3,
        fetched_object_cnt_max = 5
    })

    local gql_wrapper = graphql.new({
        schemas = data.meta.schemas,
        collections = data.meta.collections,
        accessor = accessor,
    })
    data.fill_test_data(virtbox)
    local query = [[
        query object_result_max($user_id: Int, $description: String) {
            user_collection(id: $user_id) {
                id
                last_name
                first_name
                order_connection(description: $description){
                    id
                    user_id
                    description
                }
            }
        }
    ]]

    local gql_query = gql_wrapper:compile(query)
    local variables = {
        user_id = 5,
    }
    local ok, result = pcall(gql_query.execute, gql_query, variables)
    assert(ok == false, "this test should fail")
    test:like(result,
              'count%[4%] exceeds limit%[3%] %(`resulting_object_cnt_max`',
              'resulting_object_cnt_max test')
    variables = {
        user_id = 5,
        description = "no such description"
    }
    ok, result = pcall(gql_query.execute, gql_query, variables)
    assert(ok == false, "this test should fail")
    test:like(result,
              'count%[6%] exceeds limit%[5%] %(`fetched_object_cnt_max`',
              'resulting_object_cnt_max test')


end

multirunner.run(test_run,
                data.init_spaces,
                data.drop_spaces,
                run)

os.exit(test:check() == true and 0 or 1)
