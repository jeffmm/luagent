--[[
  weather_agent.lua - Weather agent example inspired by Pydantic AI

  This demonstrates the same capabilities as the Pydantic AI weather agent:
  - Multiple tools that chain together (geocoding -> weather lookup)
  - Dependency injection for HTTP client
  - Structured output
  - Real API calls

  Usage:
    lua weather_agent.lua

  Requirements:
    - set any supported provider API key (e.g. OPENAI_API_KEY)
    - luarocks install dkjson
    - luarocks install luasocket luasec
--]]

local luagent = require("luagent")
local agent_config = luagent.detect_provider()
assert(agent_config, "No LLM provider API key detected.")

---@class WeatherData
---@field temperature number
---@field condition string
---@field humidity number
---@field wind_speed number

---@class Coordinates
---@field lat number
---@field lng number

-- Mock geocoding service (in real app, would call actual geocoding API)
-- Maps location descriptions to lat/lng coordinates
local location_database = {
	["San Francisco"] = { lat = 37.7749, lng = -122.4194 },
	["New York"] = { lat = 40.7128, lng = -74.0060 },
	["London"] = { lat = 51.5074, lng = -0.1278 },
	["Tokyo"] = { lat = 35.6762, lng = 139.6503 },
	["Paris"] = { lat = 48.8566, lng = 2.3522 },
	["Sydney"] = { lat = -33.8688, lng = 151.2093 },
	["Miami"] = { lat = 25.7617, lng = -80.1918 },
	["Seattle"] = { lat = 47.6062, lng = -122.3321 },
}

-- Mock weather service (in real app, would call actual weather API like OpenWeatherMap)
-- Maps coordinates to weather data
---@param lat number
---@param lng number
---@return WeatherData
local function get_mock_weather_data(lat, lng)
	-- Simple mock: use latitude to determine temperature
	-- Closer to equator = warmer
	local abs_lat = math.abs(lat)
	local base_temp = 90 - (abs_lat * 0.8)

	-- Add some variety based on longitude
	local variation = (lng % 10) - 5
	local temp = math.floor(base_temp + variation)

	-- Determine conditions based on temperature
	local conditions = {
		"Sunny",
		"Partly Cloudy",
		"Cloudy",
		"Rainy",
		"Foggy",
	}
	local condition_index = math.floor((temp % 5)) + 1
	local condition = conditions[condition_index]

	return {
		temperature = temp,
		condition = condition,
		humidity = 50 + (lng % 30),
		wind_speed = 5 + (lat % 15),
	}
end

-- Create the weather agent
---@return Agent
local function create_weather_agent()
	return luagent.Agent.new({
		model = agent_config.model, -- Model name from local llama.cpp server
		base_url = agent_config.base_url, -- Local llama.cpp server
		temperature = 0.7, -- Balanced temperature for tool calling
		api_key = agent_config.api_key, -- Local server doesn't need API key
		system_prompt = [[You are a helpful weather assistant.

To answer weather queries, you MUST:
1. ALWAYS call get_lat_lng first to convert the location to coordinates
2. ALWAYS call get_weather with those coordinates to get weather data
3. Then provide a friendly response with the weather information

IMPORTANT: You must call BOTH tools for every weather query. Do not skip the get_weather call.]],

		tools = {
			-- Tool 1: Geocoding - Convert location name to coordinates
			get_lat_lng = {
				description = "Convert a location name or description into latitude and longitude coordinates",
				parameters = {
					type = "object",
					properties = {
						location = {
							type = "string",
							description = "The location name, city, or address to geocode",
						},
					},
					required = { "location" },
				},
				func = function(ctx, args)
					local location = args.location

					-- Try to find exact match first
					if location_database[location] then
						return {
							location = location,
							latitude = location_database[location].lat,
							longitude = location_database[location].lng,
						}
					end

					-- Try case-insensitive partial match
					for city, coords in pairs(location_database) do
						if
							string.lower(city):find(string.lower(location), 1, true)
							or string.lower(location):find(string.lower(city), 1, true)
						then
							return {
								location = city,
								latitude = coords.lat,
								longitude = coords.lng,
							}
						end
					end

					-- Location not found
					return {
						error = "Location not found: " .. location,
						available_locations = {
							"San Francisco",
							"New York",
							"London",
							"Tokyo",
							"Paris",
							"Sydney",
							"Miami",
							"Seattle",
						},
					}
				end,
			},

			-- Tool 2: Weather lookup - Get weather for coordinates
			get_weather = {
				description = "Get current weather information for specific latitude and longitude coordinates",
				parameters = {
					type = "object",
					properties = {
						latitude = {
							type = "number",
							description = "Latitude coordinate (-90 to 90)",
						},
						longitude = {
							type = "number",
							description = "Longitude coordinate (-180 to 180)",
						},
					},
					required = { "latitude", "longitude" },
				},
				func = function(ctx, args)
					local lat = args.latitude
					local lng = args.longitude

					-- Validate coordinates
					if lat < -90 or lat > 90 or lng < -180 or lng > 180 then
						return {
							error = "Invalid coordinates. Latitude must be -90 to 90, longitude -180 to 180",
						}
					end

					-- Get weather data (in real app, would make HTTP request to weather API)
					local weather = get_mock_weather_data(lat, lng)

					return {
						latitude = lat,
						longitude = lng,
						temperature_fahrenheit = weather.temperature,
						condition = weather.condition,
						humidity_percent = weather.humidity,
						wind_speed_mph = weather.wind_speed,
					}
				end,
			},
		},
	})
end

-- Example 1: Basic weather query
---@return nil
local function example1()
	print("\n=== Example 1: Basic Weather Query ===")
	local agent = create_weather_agent()

	local result = agent:run("What's the weather like in San Francisco?")
	print("\nAgent Response:")
	print(result.data or "(empty)")

	-- Show the tool calls that were made
	print("\n--- Tool Call Trace ---")
	local tool_count = 0
	for i, msg in ipairs(result.messages) do
		if msg.role == "assistant" and msg.tool_calls then
			for _, tc in ipairs(msg.tool_calls) do
				tool_count = tool_count + 1
				print(
					string.format("%d. Tool called: %s(%s)", tool_count, tc["function"].name, tc["function"].arguments)
				)
			end
		elseif msg.role == "tool" then
			print(string.format("   Tool result: %s", msg.content))
		elseif msg.role == "assistant" and msg.content then
			print(string.format("   Assistant: %s", msg.content:sub(1, 200)))
		end
	end

	if tool_count == 0 then
		print("(No tools were called)")
	end

	print(string.format("\nTotal messages exchanged: %d", #result.messages))
end

-- Example 2: Multiple locations
---@return nil
local function example2()
	print("\n=== Example 2: Comparing Multiple Locations ===")
	local agent = create_weather_agent()

	local result = agent:run("Compare the weather in New York and Tokyo")
	print("\nAgent Response:")
	print(result.data)
end

-- Example 3: With structured output
---@return nil
local function example3()
	print("\n=== Example 3: Structured Weather Output ===")

	local agent = luagent.Agent.new({
		model = agent_config.model, -- Model name from local llama.cpp server
		base_url = agent_config.base_url, -- Local llama.cpp server
		temperature = 0.3,
		api_key = agent_config.api_key, -- Local server doesn't need API key
		system_prompt = "You are a weather assistant. Use the tools to get weather data and format it according to the output schema.",

		-- Add structured output schema
		output_schema = {
			type = "object",
			properties = {
				location = {
					type = "string",
					description = "The location name",
				},
				temperature = {
					type = "number",
					description = "Temperature in Fahrenheit",
				},
				condition = {
					type = "string",
					description = "Weather condition (e.g., Sunny, Rainy)",
				},
				summary = {
					type = "string",
					description = "A brief weather summary",
				},
			},
			required = { "location", "temperature", "condition", "summary" },
			additionalProperties = false,
		},

		tools = {
			get_lat_lng = {
				description = "Convert a location name to coordinates",
				parameters = {
					type = "object",
					properties = {
						location = { type = "string" },
					},
					required = { "location" },
				},
				func = function(ctx, args)
					local loc = location_database[args.location]
					if loc then
						return { location = args.location, latitude = loc.lat, longitude = loc.lng }
					else
						return { error = "Location not found" }
					end
				end,
			},

			get_weather = {
				description = "Get weather for coordinates",
				parameters = {
					type = "object",
					properties = {
						latitude = { type = "number" },
						longitude = { type = "number" },
					},
					required = { "latitude", "longitude" },
				},
				func = function(ctx, args)
					local weather = get_mock_weather_data(args.latitude, args.longitude)
					return {
						temperature_fahrenheit = weather.temperature,
						condition = weather.condition,
					}
				end,
			},
		},
	})

	local result = agent:run("What's the weather in London?")
	print("\nStructured Output:")
	print("Location: " .. result.data.location)
	print("Temperature: " .. result.data.temperature .. "°F")
	print("Condition: " .. result.data.condition)
	print("Summary: " .. result.data.summary)
end

-- Example 4: With dependency injection
---@return nil
local function example4()
	print("\n=== Example 4: Dependency Injection ===")

	-- Simulate different API clients or configuration
	---@return Agent
	local function create_agent_with_deps()
		return luagent.Agent.new({
			model = agent_config.model, -- Model name from local llama.cpp server
			base_url = agent_config.base_url, -- Local llama.cpp server
			temperature = 0.3,
			api_key = agent_config.api_key, -- Local server doesn't need API key
			system_prompt = function(ctx)
				local units = ctx.deps.temperature_units or "fahrenheit"
				return string.format(
					"You are a weather assistant. Report temperatures in %s. Use the tools to get weather data.",
					units
				)
			end,

			tools = {
				get_lat_lng = {
					description = "Get coordinates for a location",
					parameters = {
						type = "object",
						properties = { location = { type = "string" } },
						required = { "location" },
					},
					func = function(ctx, args)
						local loc = location_database[args.location]
						if loc then
							return { latitude = loc.lat, longitude = loc.lng }
						else
							return { error = "Location not found" }
						end
					end,
				},

				get_weather = {
					description = "Get weather for coordinates",
					parameters = {
						type = "object",
						properties = {
							latitude = { type = "number" },
							longitude = { type = "number" },
						},
						required = { "latitude", "longitude" },
					},
					func = function(ctx, args)
						local weather = get_mock_weather_data(args.latitude, args.longitude)

						-- Convert temperature based on user preference
						local temp = weather.temperature
						if ctx.deps.temperature_units == "celsius" then
							temp = math.floor((temp - 32) * 5 / 9)
						end

						return {
							temperature = temp,
							units = ctx.deps.temperature_units or "fahrenheit",
							condition = weather.condition,
						}
					end,
				},
			},
		})
	end

	local agent = create_agent_with_deps()

	-- Use with Fahrenheit (default)
	local result1 = agent:run("What's the weather in Miami?", {
		deps = { temperature_units = "fahrenheit" },
	})
	print("\nFahrenheit:")
	print(result1.data)

	-- Use with Celsius
	local result2 = agent:run("What's the weather in Miami?", {
		deps = { temperature_units = "celsius" },
	})
	print("\nCelsius:")
	print(result2.data)
end

-- Main execution
---@return nil
local function main()
	print("=== Weather Agent - Pydantic AI Inspired Example ===")
	print("This demonstrates:")
	print("- Multiple tools chaining together (geocoding -> weather)")
	print("- Dependency injection")
	print("- Structured outputs")
	print("- Real agent/LLM interaction")

	-- Check if llama.cpp server is configured
	print("\nConfiguration:")
	print("- Model: " .. agent_config.model)
	print("- Base URL: " .. agent_config.base_url)
	print("\nRunning examples...\n")

	-- Run examples (comment out the ones you don't want to run)
	example1() -- Basic weather query
	example2() -- Multiple locations
	example3() -- Structured output (requires strict schema support)
	example4() -- Dependency injection

	print("\n=== Examples Complete ===")
end

-- Run the examples
main()
