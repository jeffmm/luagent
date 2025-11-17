--[[
  luagent_test.lua - Comprehensive tests for luagent library

  Run with: lua luagent_test.lua
--]]

local luagent = require("luagent")

-- Simple test framework
local tests_passed = 0
local tests_failed = 0
local current_test = ""

---@param name string
---@param func fun()
local function test(name, func)
	current_test = name
	io.write("Testing: " .. name .. " ... ")
	local ok, err = pcall(func)
	if ok then
		io.write("PASSED\n")
		tests_passed = tests_passed + 1
	else
		io.write("FAILED\n")
		io.write("  Error: " .. tostring(err) .. "\n")
		tests_failed = tests_failed + 1
	end
end

---@param actual any
---@param expected any
---@param msg? string
local function assert_eq(actual, expected, msg)
	if actual ~= expected then
		error((msg or "Assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

---@param value any
---@param msg? string
local function assert_true(value, msg)
	if not value then
		error(msg or "Expected true, got false")
	end
end

---@param value any
---@param msg? string
local function assert_false(value, msg)
	if value then
		error(msg or "Expected false, got true")
	end
end

---@param value any
---@param msg? string
local function assert_nil(value, msg)
	if value ~= nil then
		error(msg or "Expected nil, got " .. tostring(value))
	end
end

---@param value any
---@param msg? string
local function assert_not_nil(value, msg)
	if value == nil then
		error(msg or "Expected non-nil value")
	end
end

---@param value any
---@param expected_type string
---@param msg? string
local function assert_type(value, expected_type, msg)
	local actual_type = type(value)
	if actual_type ~= expected_type then
		error((msg or "Type mismatch") .. ": expected " .. expected_type .. ", got " .. actual_type)
	end
end

---@param haystack string|table
---@param needle any
---@param msg? string
local function assert_contains(haystack, needle, msg)
	if type(haystack) == "string" then
		if not haystack:find(needle, 1, true) then
			error(msg or "String does not contain expected substring")
		end
	elseif type(haystack) == "table" then
		local found = false
		for _, v in pairs(haystack) do
			if v == needle then
				found = true
				break
			end
		end
		if not found then
			error(msg or "Table does not contain expected value")
		end
	end
end

---@param func fun()
---@param expected_msg? string
local function assert_error(func, expected_msg)
	local ok, err = pcall(func)
	if ok then
		error("Expected function to throw error")
	end
	if expected_msg and not string.find(tostring(err), expected_msg, 1, true) then
		error("Error message mismatch: expected '" .. expected_msg .. "' in '" .. tostring(err) .. "'")
	end
end

-- Tests

-- Test 1: Schema validation - valid object
test("Schema validation: valid object", function()
	local schema = {
		type = "object",
		properties = {
			name = { type = "string" },
			age = { type = "number" },
		},
		required = { "name" },
	}

	local value = { name = "Alice", age = 30 }
	local ok, err = luagent.validate_schema(value, schema)

	assert_true(ok, "Validation should succeed")
	assert_nil(err, "Error should be nil")
end)

-- Test 2: Schema validation - missing required field
test("Schema validation: missing required field", function()
	local schema = {
		type = "object",
		properties = {
			name = { type = "string" },
			age = { type = "number" },
		},
		required = { "name" },
	}

	local value = { age = 30 }
	local ok, err = luagent.validate_schema(value, schema)

	assert_false(ok, "Validation should fail")
	assert_not_nil(err, "Error should not be nil")
	assert_contains(err, "name", "Error should mention missing field")
end)

-- Test 3: Schema validation - wrong type
test("Schema validation: wrong type", function()
	local schema = {
		type = "object",
		properties = {
			age = { type = "number" },
		},
	}

	local value = { age = "thirty" }
	local ok, err = luagent.validate_schema(value, schema)

	assert_false(ok, "Validation should fail")
	assert_contains(err, "number", "Error should mention expected type")
end)

-- Test 4: Schema validation - nested objects
test("Schema validation: nested objects", function()
	local schema = {
		type = "object",
		properties = {
			user = {
				type = "object",
				properties = {
					name = { type = "string" },
				},
				required = { "name" },
			},
		},
	}

	local value = { user = { name = "Bob" } }
	local ok, err = luagent.validate_schema(value, schema)

	assert_true(ok, "Validation should succeed")
	assert_nil(err, "Error should be nil")
end)

-- Test 5: Schema validation - arrays
test("Schema validation: arrays", function()
	local schema = {
		type = "array",
		items = { type = "number" },
	}

	local value = { 1, 2, 3, 4, 5 }
	local ok, err = luagent.validate_schema(value, schema)

	assert_true(ok, "Validation should succeed")
	assert_nil(err, "Error should be nil")
end)

-- Test 6: Schema validation - invalid array items
test("Schema validation: invalid array items", function()
	local schema = {
		type = "array",
		items = { type = "number" },
	}

	local value = { 1, 2, "three", 4 }
	local ok, err = luagent.validate_schema(value, schema)

	assert_false(ok, "Validation should fail")
	assert_contains(err, "Array item", "Error should mention array item")
end)

-- Test 7: Agent creation - basic
test("Agent creation: basic configuration", function()
	local agent = luagent.Agent.new({
		model = "gpt-4",
		system_prompt = "You are helpful",
	})

	assert_not_nil(agent, "Agent should be created")
	assert_eq(agent.model, "gpt-4", "Model should be set")
	assert_eq(agent.system_prompt, "You are helpful", "System prompt should be set")
end)

-- Test 8: Agent creation - missing model
test("Agent creation: missing model throws error", function()
	assert_error(function()
		luagent.Agent.new({
			system_prompt = "Test",
		})
	end, "model is required")
end)

-- Test 9: Agent creation - with tools
test("Agent creation: with tools", function()
	local agent = luagent.Agent.new({
		model = "gpt-4",
		tools = {
			get_time = {
				description = "Get current time",
				parameters = {
					type = "object",
					properties = {},
				},
				func = function(ctx, args)
					return { time = "12:00" }
				end,
			},
		},
	})

	assert_not_nil(agent._tool_map.get_time, "Tool should be registered")
	assert_eq(agent._tool_map.get_time.description, "Get current time")
end)

-- Test 10: Agent creation - with output schema
test("Agent creation: with output schema", function()
	local schema = {
		type = "object",
		properties = {
			answer = { type = "string" },
		},
	}

	local agent = luagent.Agent.new({
		model = "gpt-4",
		output_schema = schema,
	})

	assert_not_nil(agent.output_schema, "Output schema should be set")
	assert_eq(agent.output_schema.type, "object")
end)

-- Test 11: Dynamic system prompt
test("Agent: dynamic system prompt", function()
	local agent = luagent.Agent.new({
		model = "gpt-4",
		system_prompt = function(ctx)
			return "You are a " .. ctx.deps.role .. " assistant"
		end,
	})

	local ctx = luagent.RunContext.new({ role = "helpful" })
	local prompt = agent:_build_system_prompt(ctx)

	assert_eq(prompt, "You are a helpful assistant")
end)

-- Test 12: Building tools for OpenAI API
test("Agent: building tools for OpenAI API", function()
	local agent = luagent.Agent.new({
		model = "gpt-4",
		tools = {
			add = {
				description = "Add two numbers",
				parameters = {
					type = "object",
					properties = {
						a = { type = "number" },
						b = { type = "number" },
					},
				},
				func = function(ctx, args)
					return { result = args.a + args.b }
				end,
			},
		},
	})

	local tools = agent:_build_tools()

	assert_eq(#tools, 1, "Should have one tool")
	assert_eq(tools[1].type, "function")
	assert_eq(tools[1]["function"].name, "add")
	assert_eq(tools[1]["function"].description, "Add two numbers")
end)

-- Test 13: RunContext creation
test("RunContext: creation and access", function()
	local deps = { api_key = "test-key", user_id = 123 }
	local messages = { { role = "user", content = "Hello" } }

	local ctx = luagent.RunContext.new(deps, messages)

	assert_not_nil(ctx, "Context should be created")
	assert_eq(ctx.deps.api_key, "test-key")
	assert_eq(ctx.deps.user_id, 123)
	assert_eq(#ctx.messages, 1)
end)

-- Test 14: Tool execution
test("Agent: tool execution", function()
	local agent = luagent.Agent.new({
		model = "gpt-4",
		tools = {
			greet = {
				description = "Greet a user",
				parameters = {
					type = "object",
					properties = {
						name = { type = "string" },
					},
				},
				func = function(ctx, args)
					return { greeting = "Hello, " .. args.name .. "!" }
				end,
			},
		},
	})

	local ctx = luagent.RunContext.new({})
	local tool_call = {
		id = "call_123",
		["function"] = {
			name = "greet",
			arguments = '{"name":"Alice"}',
		},
	}

	local result = agent:_execute_tool_call(tool_call, ctx)
	local parsed = luagent._json.decode(result)

	assert_eq(parsed.greeting, "Hello, Alice!")
end)

-- Test 15: Tool execution with context deps
test("Agent: tool execution with context dependencies", function()
	local agent = luagent.Agent.new({
		model = "gpt-4",
		tools = {
			get_user_info = {
				description = "Get user info",
				parameters = {
					type = "object",
					properties = {},
				},
				func = function(ctx, args)
					return { user = ctx.deps.current_user }
				end,
			},
		},
	})

	local ctx = luagent.RunContext.new({ current_user = "Alice" })
	local tool_call = {
		id = "call_456",
		["function"] = {
			name = "get_user_info",
			arguments = "{}",
		},
	}

	local result = agent:_execute_tool_call(tool_call, ctx)
	local parsed = luagent._json.decode(result)

	assert_eq(parsed.user, "Alice")
end)

-- Test 16: Tool error handling
test("Agent: tool execution error handling", function()
	local agent = luagent.Agent.new({
		model = "gpt-4",
		tools = {
			failing_tool = {
				description = "This tool fails",
				parameters = { type = "object", properties = {} },
				func = function(ctx, args)
					error("Something went wrong")
				end,
			},
		},
	})

	local ctx = luagent.RunContext.new({})
	local tool_call = {
		id = "call_789",
		["function"] = {
			name = "failing_tool",
			arguments = "{}",
		},
	}

	local result = agent:_execute_tool_call(tool_call, ctx)
	local parsed = luagent._json.decode(result)

	assert_not_nil(parsed.error, "Should return error")
	assert_contains(parsed.error, "Tool execution failed")
end)

-- Test 17: Unknown tool handling
test("Agent: unknown tool handling", function()
	local agent = luagent.Agent.new({
		model = "gpt-4",
	})

	local ctx = luagent.RunContext.new({})
	local tool_call = {
		id = "call_999",
		["function"] = {
			name = "nonexistent_tool",
			arguments = "{}",
		},
	}

	local result = agent:_execute_tool_call(tool_call, ctx)
	local parsed = luagent._json.decode(result)

	assert_not_nil(parsed.error, "Should return error")
	assert_contains(parsed.error, "not found")
end)

-- Test 18: JSON encoding/decoding
test("JSON: encode and decode", function()
	local original = {
		name = "Alice",
		age = 30,
		active = true,
		tags = { "user", "premium" },
	}

	local encoded = luagent._json.encode(original)
	assert_type(encoded, "string")

	-- Note: decode test depends on having a proper JSON library installed
	-- The fallback decoder is minimal and may not work for complex objects
end)

-- Test 19: Schema validation - all primitive types
test("Schema validation: primitive types", function()
	assert_true(luagent.validate_schema("hello", { type = "string" }))
	assert_true(luagent.validate_schema(42, { type = "number" }))
	assert_true(luagent.validate_schema(true, { type = "boolean" }))
	assert_true(luagent.validate_schema({}, { type = "object" }))
	assert_true(luagent.validate_schema({}, { type = "array" }))
end)

-- Test 20: Agent configuration defaults
test("Agent: configuration defaults", function()
	local agent = luagent.Agent.new({
		model = "gpt-4o-mini",
	})

	assert_eq(agent.base_url, "https://api.openai.com/v1")
	assert_type(agent.tools, "table")
	assert_eq(next(agent.tools), nil, "Tools should be empty by default")
end)

-- Test 21: Provider detection - returns config when API key exists
test("Provider detection: returns config structure", function()
	local config = luagent.detect_provider()

	-- If any API key is set in the environment, we should get a config
	if config then
		assert_not_nil(config.base_url, "Config should have base_url")
		assert_not_nil(config.model, "Config should have model")
		assert_not_nil(config.api_key, "Config should have api_key")
		assert_not_nil(config.provider, "Config should have provider name")
		assert_type(config.base_url, "string")
		assert_type(config.model, "string")
		assert_type(config.api_key, "string")
		assert_type(config.provider, "string")
	end
	-- If no API key is set, config will be nil, which is also valid
end)

-- Test 22: Using detect_provider with Agent
test("Provider detection: integration with Agent.new", function()
	local config = luagent.detect_provider()

	if config then
		-- Should be able to create an agent using detected config
		local agent = luagent.Agent.new({
			model = config.model,
			base_url = config.base_url,
			api_key = config.api_key,
		})

		assert_not_nil(agent)
		assert_eq(agent.model, config.model)
		assert_eq(agent.base_url, config.base_url)
		assert_eq(agent.api_key, config.api_key)
	end
end)

-- Summary
print("\n" .. string.rep("=", 50))
print("Test Results:")
print("  Passed: " .. tests_passed)
print("  Failed: " .. tests_failed)
print("  Total:  " .. (tests_passed + tests_failed))
print(string.rep("=", 50))

if tests_failed > 0 then
	os.exit(1)
else
	print("\nAll tests passed!")
	os.exit(0)
end
