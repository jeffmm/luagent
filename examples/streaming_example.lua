--[[
  streaming_example.lua - Demonstrates streaming capabilities in luagent

  This example shows how to use the streaming API to receive incremental
  responses from the LLM, including content chunks and tool call deltas.

  Run with:
    export OPENAI_API_KEY="your-key-here"
    eval "$(luarocks path)" && lua examples/streaming_example.lua
--]]

local luagent = require("luagent")

-- Example 1: Basic streaming with content
local function example_basic_streaming()
	print("\n=== Example 1: Basic Content Streaming ===\n")

	local config = luagent.detect_provider()
	if not config then
		print("Error: No API key found. Set OPENAI_API_KEY or another provider's API key.")
		return
	end

	local agent = luagent.Agent.new({
		model = config.model,
		base_url = config.base_url,
		api_key = config.api_key,
		system_prompt = "You are a helpful assistant. Be concise.",
	})

	print("Streaming response: ")
	io.write("> ")

	local result = agent:run("Write a short haiku about Lua programming", {
		stream = true,
		on_chunk = function(chunk_type, data)
			if chunk_type == "content" then
				-- Print each content chunk as it arrives
				io.write(data.content)
				io.flush()
			end
		end,
	})

	print("\n\nFinal accumulated result:")
	print(result.data)
end

-- Example 2: Streaming with tool calls
local function example_streaming_with_tools()
	print("\n=== Example 2: Streaming with Tool Calls ===\n")

	local config = luagent.detect_provider()
	if not config then
		print("Error: No API key found. Set OPENAI_API_KEY or another provider's API key.")
		return
	end

	local agent = luagent.Agent.new({
		model = config.model,
		base_url = config.base_url,
		api_key = config.api_key,
		system_prompt = "You are a helpful weather assistant.",
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
						units = {
							type = "string",
							description = "Temperature units (celsius or fahrenheit)",
							enum = { "celsius", "fahrenheit" },
						},
					},
					required = { "city" },
				},
				func = function(ctx, args)
					-- Simulate weather API call
					local temp = args.units == "celsius" and 22 or 72
					return {
						city = args.city,
						temperature = temp,
						units = args.units or "fahrenheit",
						condition = "sunny",
					}
				end,
			},
		},
	})

	print("Asking about weather...\n")

	local result = agent:run("What's the weather like in Paris?", {
		stream = true,
		on_chunk = function(chunk_type, data)
			if chunk_type == "content" then
				io.write(data.content)
				io.flush()
			elseif chunk_type == "tool_call_start" then
				print(string.format("\n[Tool call started: %s]", data.id))
			elseif chunk_type == "tool_call_delta" then
				-- Show incremental tool arguments
				io.write(data.arguments)
				io.flush()
			elseif chunk_type == "tool_call_end" then
				print(string.format("\n[Tool call completed: %s]", data.tool_call["function"].name))
			end
		end,
	})

	print("\n\nFinal result:")
	print(result.data)
end

-- Example 3: Monitoring streaming progress
local function example_streaming_progress()
	print("\n=== Example 3: Streaming Progress Monitoring ===\n")

	local config = luagent.detect_provider()
	if not config then
		print("Error: No API key found. Set OPENAI_API_KEY or another provider's API key.")
		return
	end

	local agent = luagent.Agent.new({
		model = config.model,
		base_url = config.base_url,
		api_key = config.api_key,
	})

	local stats = {
		content_chunks = 0,
		total_chars = 0,
		tool_calls = 0,
	}

	print("Generating a longer response to show progress...\n")

	local result = agent:run("Explain what Lua is in 3-4 sentences.", {
		stream = true,
		on_chunk = function(chunk_type, data)
			if chunk_type == "content" then
				stats.content_chunks = stats.content_chunks + 1
				stats.total_chars = stats.total_chars + #data.content
				io.write(data.content)
				io.flush()
			elseif chunk_type == "tool_call_start" then
				stats.tool_calls = stats.tool_calls + 1
			end
		end,
	})

	print("\n\nStreaming Statistics:")
	print(string.format("  Content chunks received: %d", stats.content_chunks))
	print(string.format("  Total characters: %d", stats.total_chars))
	print(string.format("  Tool calls: %d", stats.tool_calls))
end

-- Example 4: Non-streaming comparison
local function example_non_streaming()
	print("\n=== Example 4: Non-Streaming (for comparison) ===\n")

	local config = luagent.detect_provider()
	if not config then
		print("Error: No API key found. Set OPENAI_API_KEY or another provider's API key.")
		return
	end

	local agent = luagent.Agent.new({
		model = config.model,
		base_url = config.base_url,
		api_key = config.api_key,
	})

	print("Fetching response (non-streaming)...")
	print("(Notice the wait before the response appears)\n")

	-- Regular run without streaming
	local result = agent:run("Write a short haiku about Lua programming")

	print("Response:")
	print(result.data)
end

-- Run examples
print("=== Luagent Streaming Examples ===")
print("\nNote: These examples require an API key to be set in your environment.")
print("Uncomment the example you want to run below.\n")

-- Uncomment to run examples:
-- example_basic_streaming()
-- example_streaming_with_tools()
-- example_streaming_progress()
-- example_non_streaming()

print("\nTo run an example, uncomment one of the function calls above and run:")
print("  eval \"$(luarocks path)\" && lua examples/streaming_example.lua")
