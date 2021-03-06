#!/usr/bin/env tarantool

-- requires
-- --------

local fio = require('fio')

-- require in-repo version of graphql/ sources despite current working directory
package.path = fio.abspath(debug.getinfo(1).source:match("@?(.*/)")
    :gsub('/./', '/'):gsub('/+$', '')) .. '/../../?.lua' .. ';' .. package.path

local bench = require('test.bench.bench')
local testdata = require('test.testdata.bench_testdata')

-- functions
-- ---------

local function bench_prepare(state)
    local virtbox = state.shard or box.space

    state.gql_wrapper = bench.graphql_from_testdata(testdata, state.shard)
    testdata.fill_test_data(virtbox)

    local query = [[
        query match_users {
            user {
                user_id
                first_name
                middle_name
                last_name
            }
        }
    ]]
    state.variables = {}
    state.gql_query = state.gql_wrapper:compile(query)
end

local function bench_iter(state)
    return state.gql_query:execute(state.variables)
end

-- run
-- ---

box.cfg({})

bench.run('nesting-1-100', {
    init_function = testdata.init_spaces,
    cleanup_function = testdata.drop_spaces,
    bench_prepare = bench_prepare,
    bench_iter = bench_iter,
    iterations = {
        space = 10000,
        shard = 10000,
    },
    checksums = {
        space = 3027774793,
        shard = 3027774793,
    },
})

os.exit()
