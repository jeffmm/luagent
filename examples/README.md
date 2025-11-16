# luagent Examples

This directory contains examples demonstrating luagent's capabilities for building AI agents in Lua.

## Quick Start

### Prerequisites

```bash
# Install required dependencies
luarocks install dkjson

# Install HTTP library (choose one)
luarocks install lua-requests
# OR
luarocks install luasocket luasec

# Set your API key (choose one provider)
export OPENAI_API_KEY="your-key-here"
# OR export XAI_API_KEY, ANTHROPIC_API_KEY, TOGETHER_API_KEY, GROQ_API_KEY
```

### Run Examples

```bash
# Run the basic examples collection
eval "$(luarocks path)" && lua example.lua

# Run the weather agent example
eval "$(luarocks path)" && lua weather_agent.lua
```

## Available Examples

### 1. `example.lua` - Feature Demonstrations

A collection of small, focused examples demonstrating individual luagent features. Perfect for learning the library step-by-step.

**Examples included:**

| Example | Feature | Description |
|---------|---------|-------------|
| Example 0 | Auto-detect Provider | Automatically detect AI provider from environment variables |
| Example 1 | Basic Agent | Simple agent with text input/output |
| Example 2 | Structured Output | JSON schema validation for consistent responses |
| Example 3 | Dynamic System Prompts | Adapt agent behavior based on runtime context |
| Example 4 | Tool Calling | Single tool integration with mock data |
| Example 5 | Multiple Tools | Complex tool interactions with dependency injection |
| Example 6 | Message History | Multi-turn conversations with context |

**When to use this file:**
- Learning luagent for the first time
- Understanding specific features in isolation
- Quick testing and experimentation
- Building your own custom agents

**Running:**
```bash
eval "$(luarocks path)" && lua example.lua
```

Note: Examples are enabled by default. Comment out any you don't want to run.

### 2. `weather_agent.lua` - End-to-End Application

A complete weather assistant inspired by the [Pydantic AI weather agent example](https://ai.pydantic.dev/examples/weather-agent/). Demonstrates how multiple features work together in a real application.

**Features demonstrated:**

- **Tool Chaining**: Two tools working sequentially (geocoding → weather lookup)
- **Dependency Injection**: Runtime configuration for temperature units
- **Structured Outputs**: JSON schema validation for consistent weather data
- **Error Handling**: Graceful handling of invalid locations and coordinates
- **Mock Services**: Simulated geocoding and weather APIs

**How it works:**

When you ask "What's the weather in San Francisco?", the agent:

1. Calls `get_lat_lng("San Francisco")` → returns `{lat: 37.7749, lng: -122.4194}`
2. Calls `get_weather(37.7749, -122.4194)` → returns weather data
3. Provides a natural language response with temperature, conditions, humidity, wind

**When to use this file:**
- Understanding how to build complete agents
- Learning tool chaining patterns
- Seeing best practices in action
- Reference implementation for your own agents

**Running:**
```bash
eval "$(luarocks path)" && lua weather_agent.lua
```

All four examples run by default. Edit the `main()` function to run specific examples.

## Key Concepts

### Structured Outputs

Both examples demonstrate JSON schema validation:

```lua
output_schema = {
  type = "object",
  properties = {
    sentiment = { type = "string", enum = {"positive", "negative", "neutral"} },
    confidence = { type = "number" }
  },
  required = {"sentiment", "confidence"}
}
```

The agent's response will be validated against this schema automatically.

### Dynamic System Prompts

System prompts can adapt based on runtime context:

```lua
system_prompt = function(ctx)
  local units = ctx.deps.temperature_units or "fahrenheit"
  return string.format("Report temperatures in %s.", units)
end
```

### Tool Calling

Tools define their interface via JSON schemas:

```lua
tools = {
  get_weather = {
    description = "Get current weather for a city",
    parameters = {
      type = "object",
      properties = {
        city = { type = "string", description = "City name" }
      },
      required = {"city"}
    },
    func = function(ctx, args)
      -- ctx.deps contains injected dependencies
      return { temperature = 72, condition = "Sunny" }
    end
  }
}
```

### Dependency Injection

Pass runtime dependencies to customize agent behavior:

```lua
agent:run("What's the weather?", {
  deps = {
    database = db_connection,
    user_id = "user123",
    temperature_units = "celsius"
  }
})
```

Access dependencies in tools and dynamic prompts via `ctx.deps`.

## Example Output

### Basic Query (example.lua)
```
=== Example 1: Basic Agent ===
Answer: The capital of France is Paris.
```

### Structured Output (example.lua)
```
=== Example 2: Structured Output ===
Sentiment: positive
Confidence: 0.95
Reasoning: The phrase "absolutely love" and "exceeded all my expectations"
indicates strong positive sentiment.
```

### Weather Agent (weather_agent.lua)
```
=== Example 1: Basic Weather Query ===

Agent Response:
The current weather in San Francisco is 62°F with Cloudy conditions.
Here's more details:
- Humidity: 77.58%
- Wind Speed: 12.77 mph

--- Tool Call Trace ---
1. Tool called: get_lat_lng({"location":"San Francisco"})
   Tool result: {"location":"San Francisco","latitude":37.7749,"longitude":-122.4194}
2. Tool called: get_weather({"longitude":-122.4194,"latitude":37.7749})
   Tool result: {"temperature_fahrenheit":62,"condition":"Cloudy",...}
```

## Extending the Examples

### Add Real API Calls

Replace mock data with actual API calls:

```lua
get_weather = {
  func = function(ctx, args)
    local http = require("http.request")
    local url = string.format(
      "https://api.openweathermap.org/data/2.5/weather?lat=%f&lon=%f",
      args.latitude, args.longitude
    )
    local response = http.get(url)
    return json.decode(response)
  end
}
```

### Add More Tools

Extend agents with additional capabilities:

```lua
tools = {
  get_forecast = {...},      -- 7-day weather forecast
  get_air_quality = {...},   -- Air quality index
  get_weather_alerts = {...} -- Weather warnings
}
```

### Multi-Turn Conversations

Build stateful conversations:

```lua
local history = {}

local result1 = agent:run("What's the weather in Tokyo?")
table.insert(history, {role = "user", content = "What's the weather in Tokyo?"})
table.insert(history, {role = "assistant", content = result1.data})

local result2 = agent:run("How about tomorrow?", {message_history = history})
```

## Comparison with Pydantic AI

The weather agent example mirrors Pydantic AI's capabilities:

| Feature | Pydantic AI | luagent |
|---------|-------------|---------|
| Tool Chaining | ✅ | ✅ |
| Dependency Injection | ✅ | ✅ |
| Structured Outputs | ✅ | ✅ |
| Dynamic Prompts | ✅ | ✅ |
| Type Safety | ✅ (Python types) | ⚠️ (JSON schemas) |
| Async Operations | ✅ | ⚠️ (Lua is single-threaded) |
| Streaming | ✅ | ❌ |
| Retry Logic | ✅ | ❌ |

## Troubleshooting

### No API key detected

```
No AI provider detected!
Please set one of these environment variables:
  - OPENAI_API_KEY
  - XAI_API_KEY
  - ANTHROPIC_API_KEY
```

**Solution:** Set one of the listed environment variables with your API key.

### Module not found

```
Error: module 'dkjson' not found
```

**Solution:** Install dependencies with luarocks:
```bash
luarocks install dkjson
luarocks install lua-requests
```

### Path not set

```
Error: module 'luagent' not found
```

**Solution:** Run with proper luarocks path:
```bash
eval "$(luarocks path)" && lua example.lua
```

## Next Steps

- Read the main [README.md](../README.md) for library documentation
- Check [CLAUDE.md](../CLAUDE.md) for development guidelines
- Explore the [luagent.lua](../luagent.lua) source code (~500 lines)
- Build your own agents using these examples as templates

## Contributing

Found an issue or want to add an example? See the main repository for contribution guidelines.
