local json = require('json')

local bench_testdata = {}

function bench_testdata.get_test_metadata()
    local schemas = json.decode([[{
        "user": {
            "type": "record",
            "name": "user",
            "fields": [
                {"name": "user_id", "type": "string"},
                {"name": "first_name", "type": "string"},
                {"name": "middle_name", "type": "string*"},
                {"name": "last_name", "type": "string"}
            ]
        },
        "user_to_passport": {
            "type": "record",
            "name": "user_to_passport",
            "fields": [
                {"name": "user_id", "type": "string"},
                {"name": "passport_id", "type": "string"}
            ]
        },
        "passport": {
            "type": "record",
            "name": "passport",
            "fields": [
                {"name": "passport_id", "type": "string"},
                {"name": "number", "type": "string"}
            ]
        }
    }]])

    local collections = json.decode([[{
        "user": {
            "schema_name": "user",
            "connections": [
                {
                    "type": "1:1",
                    "name": "user_to_passport_c",
                    "destination_collection": "user_to_passport",
                    "parts": [
                        { "source_field": "user_id", "destination_field": "user_id" }
                    ],
                    "index_name": "user_id"
                }
            ]
        },
        "user_to_passport": {
            "schema_name": "user_to_passport",
            "connections": [
                {
                    "type": "1:1",
                    "name": "passport_c",
                    "destination_collection": "passport",
                    "parts": [
                        { "source_field": "passport_id", "destination_field": "passport_id" }
                    ],
                    "index_name": "passport_id"
                }
            ]
        },
        "passport": {
            "schema_name": "passport",
            "connections": []
        }
    }]])

    local service_fields = {
        user = {},
        user_to_passport = {},
        passport = {},
    }

    local indexes = {
        user = {
            user_id = {
                service_fields = {},
                fields = {'user_id'},
                index_type = 'tree',
                unique = true,
                primary = true,
            },
        },
        user_to_passport = {
            primary = {
                service_fields = {},
                fields = {'user_id', 'passport_id'},
                index_type = 'tree',
                unique = true,
                primary = true,
            },
            user_id = {
                service_fields = {},
                fields = {'user_id'},
                index_type = 'tree',
                unique = true,
                primary = false,
            },
            passport_id = {
                service_fields = {},
                fields = {'passport_id'},
                index_type = 'tree',
                unique = true,
                primary = false,
            },
        },
        passport = {
            passport_id = {
                service_fields = {},
                fields = {'passport_id'},
                index_type = 'tree',
                unique = true,
                primary = true,
            },
        },
    }

    return {
        schemas = schemas,
        collections = collections,
        service_fields = service_fields,
        indexes = indexes,
    }
end

function bench_testdata.init_spaces()
    -- user fields
    local U_USER_ID_FN = 1

    -- user_to_passport fields
    local T_USER_ID_FN = 1
    local T_PASSPORT_ID_FN = 2

    -- passport fields
    local P_PASSPORT_ID_FN = 1

    box.once('init_spaces_bench', function()
        -- user space
        box.schema.create_space('user')
        box.space.user:create_index('user_id',
            {type = 'tree', parts = {
                U_USER_ID_FN, 'string',
            }}
        )

        -- user_to_passport space
        box.schema.create_space('user_to_passport')
        box.space.user_to_passport:create_index('primary',
            {type = 'tree', parts = {
                T_USER_ID_FN, 'string',
                T_PASSPORT_ID_FN, 'string',
            }}
        )
        box.space.user_to_passport:create_index('user_id',
            {type = 'tree', parts = {
                T_USER_ID_FN, 'string',
            }}
        )
        box.space.user_to_passport:create_index('passport_id',
            {type = 'tree', parts = {
                T_PASSPORT_ID_FN, 'string',
            }}
        )

        -- passport space
        box.schema.create_space('passport')
        box.space.passport:create_index('passport_id',
            {type = 'tree', parts = {
                P_PASSPORT_ID_FN, 'string',
            }}
        )
    end)
end

function bench_testdata.fill_test_data(shard)
    local virtbox = shard or box.space

    local NULL_T = 0
    local STRING_T = 1 --luacheck: ignore

    for i = 1, 100 do
        local s = tostring(i)
        virtbox.user:replace({
            'user_id_' .. s,
            'first name ' .. s,
            NULL_T, box.NULL,
            'last name ' .. s,
        })
        virtbox.user_to_passport:replace({
            'user_id_' .. s,
            'passport_id_' .. s,
        })
        virtbox.passport:replace({
            'passport_id_' .. s,
            'number_' .. s,
        })
    end
end

function bench_testdata.drop_spaces()
    box.space._schema:delete('onceinit_spaces_bench')
    box.space.user:drop()
    box.space.user_to_passport:drop()
    box.space.passport:drop()
end

return bench_testdata
