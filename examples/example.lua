--[[
  example.lua - Examples of using the luagent library

  This file demonstrates various features of luagent including:
  - Basic agent creation and usage
  - Structured outputs with JSON schemas
  - Dynamic system prompts
  - Tool/function calling
  - Dependency injection

  To run these examples, you'll need:
  1. An OpenAI API key (set OPENAI_API_KEY env var)
  2. dkjson: luarocks install dkjson
  3. One of these HTTP libraries:
     - lua-requests: luarocks install lua-requests
     - OR luasocket + luasec: luarocks install luasocket luasec
--]]

local luagent = require("luagent")
local config = luagent.detect_provider()

if not config then
	print("No AI provider detected!")
	print("Please set one of these environment variables:")
	print("  - OPENAI_API_KEY")
	print("  - XAI_API_KEY")
	print("  - ANTHROPIC_API_KEY")
	print("  - TOGETHER_API_KEY")
	print("  - GROQ_API_KEY")
	os.exit(1)
end

-- Example 0: Auto-detect provider from environment
print("=== Example 0: Auto-detect Provider ===")

---@return nil
local function example0()
	-- Automatically detect available AI provider
	print(string.format("Detected provider: %s", config.provider))
	print(string.format("Base URL: %s", config.base_url))
	print(string.format("Model: %s", config.model))

	-- Create agent using detected configuration
	local agent = luagent.Agent.new({
		model = config.model,
		base_url = config.base_url,
		api_key = config.api_key,
		system_prompt = "You are a helpful assistant that provides concise answers.",
	})

	local result = agent:run("What is 2+2?")
	print("Answer: " .. result.data)
end

-- Uncomment to run:
example0()

-- Example 1: Basic agent with simple text output
print("\n=== Example 1: Basic Agent ===")

---@return nil
local function example1()
	local agent = luagent.Agent.new({
		model = config.model,
		base_url = config.base_url,
		api_key = config.api_key,
		system_prompt = "You are a helpful assistant that provides concise answers.",
	})

	local result = agent:run("What is the capital of France?")
	print("Answer: " .. result.data)
end

-- Uncomment to run (requires API key):
example1()

-- Example 2: Structured output with JSON schema
print("\n=== Example 2: Structured Output ===")

---@return nil
local function example2()
	local agent = luagent.Agent.new({
		model = config.model,
		base_url = config.base_url,
		api_key = config.api_key,
		system_prompt = "You analyze sentiment of text.",
		output_schema = {
			type = "object",
			properties = {
				sentiment = {
					type = "string",
					enum = { "positive", "negative", "neutral" },
				},
				confidence = {
					type = "number",
					description = "Confidence score between 0 and 1",
				},
				reasoning = {
					type = "string",
					description = "Brief explanation of the sentiment",
				},
			},
			required = { "sentiment", "confidence", "reasoning" },
			additionalProperties = false,
		},
	})

	local result = agent:run("I absolutely love this product! It exceeded all my expectations.")
	print("Sentiment: " .. result.data.sentiment)
	print("Confidence: " .. result.data.confidence)
	print("Reasoning: " .. result.data.reasoning)
end

-- Uncomment to run:
example2()

-- Example 3: Dynamic system prompt based on context
print("\n=== Example 3: Dynamic System Prompt ===")

---@return nil
local function example3()
	local agent = luagent.Agent.new({
		model = config.model,
		base_url = config.base_url,
		api_key = config.api_key,
		system_prompt = function(ctx)
			local personality = ctx.deps.personality or "helpful"
			local expertise = ctx.deps.expertise or "general"
			return string.format(
				"You are a %s assistant with expertise in %s. Respond accordingly.",
				personality,
				expertise
			)
		end,
	})

	-- Run with different personalities
	local result1 = agent:run("Explain quantum computing", {
		deps = { personality = "enthusiastic", expertise = "physics" },
	})
	print("Enthusiastic physicist: " .. result1.data)

	local result2 = agent:run("Explain quantum computing", {
		deps = { personality = "concise", expertise = "computer science" },
	})
	print("\nConcise CS expert: " .. result2.data)
end

-- Uncomment to run:
example3()

-- Example 4: Agent with tool calling
print("\n=== Example 4: Tool Calling ===")

---@return nil
local function example4()
	-- Simulated weather database
	local weather_db = {
		["San Francisco"] = { temp = 65, condition = "Foggy" },
		["New York"] = { temp = 75, condition = "Sunny" },
		["London"] = { temp = 55, condition = "Rainy" },
		["Tokyo"] = { temp = 70, condition = "Cloudy" },
	}

	local agent = luagent.Agent.new({
		model = config.model,
		base_url = config.base_url,
		api_key = config.api_key,
		system_prompt = "You are a weather assistant. Use the get_weather tool to look up weather information.",
		tools = {
			get_weather = {
				description = "Get the current weather for a city",
				parameters = {
					type = "object",
					properties = {
						city = {
							type = "string",
							description = "The city name",
						},
					},
					required = { "city" },
				},
				func = function(ctx, args)
					local city = args.city
					local weather = weather_db[city]

					if weather then
						return {
							city = city,
							temperature = weather.temp,
							condition = weather.condition,
						}
					else
						return {
							error = "Weather data not available for " .. city,
						}
					end
				end,
			},
		},
	})

	local result = agent:run("What's the weather like in San Francisco?")
	print("Response: " .. result.data)
end

-- Uncomment to run:
example4()

-- Example 5: Multiple tools with dependency injection
print("\n=== Example 5: Multiple Tools with Dependencies ===")

---@return nil
local function example5()
	local agent = luagent.Agent.new({
		model = config.model,
		base_url = config.base_url,
		api_key = config.api_key,
		system_prompt = "You are a customer service assistant. Help users with their orders.",
		output_schema = {
			type = "object",
			properties = {
				response = { type = "string" },
				order_id = { type = "string" },
				status = { type = "string" },
			},
			required = { "response" },
		},
		tools = {
			get_order_status = {
				description = "Get the status of an order",
				parameters = {
					type = "object",
					properties = {
						order_id = { type = "string" },
					},
					required = { "order_id" },
				},
				func = function(ctx, args)
					-- Access database connection from dependencies
					local db = ctx.deps.database

					-- Simulate database lookup
					local orders = {
						["ORD-123"] = "shipped",
						["ORD-456"] = "processing",
						["ORD-789"] = "delivered",
					}

					local status = orders[args.order_id] or "not found"
					return {
						order_id = args.order_id,
						status = status,
					}
				end,
			},

			update_order = {
				description = "Update an order (requires admin access)",
				parameters = {
					type = "object",
					properties = {
						order_id = { type = "string" },
						new_status = { type = "string" },
					},
					required = { "order_id", "new_status" },
				},
				func = function(ctx, args)
					-- Check permissions from dependencies
					if not ctx.deps.is_admin then
						return { error = "Unauthorized: admin access required" }
					end

					return {
						success = true,
						message = "Order " .. args.order_id .. " updated to " .. args.new_status,
					}
				end,
			},
		},
	})

	-- Run as regular user
	local result1 = agent:run("What's the status of order ORD-123?", {
		deps = {
			database = "mock_db_connection",
			is_admin = false,
		},
	})
	print("User query result: " .. result1.data.response)

	-- Run as admin
	local result2 = agent:run("Update order ORD-456 to shipped", {
		deps = {
			database = "mock_db_connection",
			is_admin = true,
		},
	})
	print("Admin query result: " .. result2.data.response)
end

-- Uncomment to run:
example5()

-- Example 6: Message history for conversation context
print("\n=== Example 6: Conversation with Message History ===")

---@return nil
local function example6()
	local agent = luagent.Agent.new({
		model = config.model,
		base_url = config.base_url,
		api_key = config.api_key,
		system_prompt = "You are a helpful tutor teaching mathematics.",
	})

	-- First question
	local result1 = agent:run("What is a prime number?")
	print("Q: What is a prime number?")
	print("A: " .. result1.data)

	-- Follow-up question using message history
	local result2 = agent:run("Can you give me an example?", {
		message_history = {
			{ role = "user", content = "What is a prime number?" },
			{ role = "assistant", content = result1.data },
		},
	})
	print("\nQ: Can you give me an example?")
	print("A: " .. result2.data)
end

-- Uncomment to run:
example6()

print("\n=== Examples Complete ===")
print("Uncomment the example function calls to run them with your API key.")
print("\nTo use these examples:")
print("1. Set your OPENAI_API_KEY environment variable")
print("2. Install dependencies: luarocks install dkjson lua-requests")
print("3. Uncomment the example() calls above")
print("4. Run: lua example.lua")
