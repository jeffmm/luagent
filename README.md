# luagent

A portable, single-file Lua library for creating composable AI agents with structured inputs/outputs and dynamic prompts. Inspired by Pydantic AI, designed to be a lightweight, functional drop-in replacement for building agents in Lua.

## Features

- **Structured Inputs/Outputs**: JSON schema validation for reliable, type-safe agent outputs
- **Dynamic Prompts**: System prompts can be static strings or functions that adapt based on runtime context
- **Tool/Function Calling**: Define tools that agents can call to interact with external systems
- **OpenAI-Compatible API**: Works with OpenAI, Ollama, Together AI, and other compatible providers
- **Dependency Injection**: Type-safe pattern for passing runtime dependencies to agents and tools
- **Portable**: Entire library in a single Lua file, easy to vendor or distribute
- **Low Complexity**: Clean, readable code with comprehensive tests

## Installation

### Option 1: Direct Download

Simply copy `luagent.lua` into your project. The library is self-contained in a single file.

### Option 2: Dependencies

For full functionality, install these optional dependencies:

```bash
# JSON library (pick one, dkjson recommended)
luarocks install dkjson

# HTTP library (pick one)
luarocks install lua-requests
# OR
luarocks install luasocket luasec
```

The library will work with any of these JSON/HTTP libraries, or fall back to basic implementations if none are available.

## Quick Start

```lua
local luagent = require('luagent')

-- Create a simple agent
local agent = luagent.Agent.new({
  model = "gpt-4o-mini",
  base_url = "https://api.openai.com/v1",
  api_key = os.getenv("OPENAI_API_KEY"),
  system_prompt = "You are a helpful assistant."
})

-- Run it
local result = agent:run("What is the capital of France?")
print(result.data)  -- "The capital of France is Paris."
```

## Examples

See `example.lua` for basic examples, and `weather_agent.lua` for a complete, real-world example inspired by Pydantic AI.

### Weather Agent Example

A complete weather agent that demonstrates tool chaining, dependency injection, and structured outputs. This example mirrors the [Pydantic AI weather agent](https://ai.pydantic.dev/examples/weather-agent/) and shows how to build a multi-tool agent that works with local LLMs.

```bash
# Run the weather agent with your local llama.cpp server
eval "$(luarocks path)" && lua weather_agent.lua
```

See [WEATHER_EXAMPLE.md](WEATHER_EXAMPLE.md) for detailed documentation.

### Structured Output

Get type-safe, validated responses using JSON schemas:

```lua
local agent = luagent.Agent.new({
  model = "gpt-4o-mini",
  system_prompt = "You analyze sentiment of text.",
  output_schema = {
    type = "object",
    properties = {
      sentiment = { type = "string", enum = {"positive", "negative", "neutral"} },
      confidence = { type = "number" },
      reasoning = { type = "string" }
    },
    required = {"sentiment", "confidence", "reasoning"}
  }
})

local result = agent:run("I love this product!")

-- Access structured data
print(result.data.sentiment)   -- "positive"
print(result.data.confidence)  -- 0.95
print(result.data.reasoning)   -- "The phrase 'I love' indicates strong positive sentiment"
```

### Dynamic System Prompts

Adapt agent behavior based on runtime context:

```lua
local agent = luagent.Agent.new({
  model = "gpt-4o-mini",
  system_prompt = function(ctx)
    return string.format(
      "You are a %s assistant with expertise in %s.",
      ctx.deps.personality,
      ctx.deps.expertise
    )
  end
})

-- Different behavior based on dependencies
local result = agent:run("Explain quantum computing", {
  deps = { personality = "enthusiastic", expertise = "physics" }
})
```

### Tool/Function Calling

Give your agent abilities by defining tools:

```lua
local agent = luagent.Agent.new({
  model = "gpt-4o-mini",
  system_prompt = "You are a weather assistant.",
  tools = {
    get_weather = {
      description = "Get the current weather for a city",
      parameters = {
        type = "object",
        properties = {
          city = { type = "string", description = "The city name" }
        },
        required = {"city"}
      },
      func = function(ctx, args)
        -- Your weather API logic here
        return {
          temperature = 72,
          condition = "sunny",
          city = args.city
        }
      end
    }
  }
})

local result = agent:run("What's the weather in San Francisco?")
-- Agent automatically calls the get_weather tool and uses the result
```

### Dependency Injection

Pass runtime dependencies to tools safely:

```lua
local agent = luagent.Agent.new({
  model = "gpt-4o-mini",
  tools = {
    query_database = {
      description = "Query the database",
      parameters = { type = "object", properties = {} },
      func = function(ctx, args)
        -- Access dependencies through context
        local db = ctx.deps.database
        local user = ctx.deps.current_user

        -- Use them in your logic
        return db:query("SELECT * FROM orders WHERE user_id = ?", user.id)
      end
    }
  }
})

-- Inject dependencies at runtime
local result = agent:run("Show my recent orders", {
  deps = {
    database = my_db_connection,
    current_user = { id = 123, name = "Alice" }
  }
})
```

### Conversation History

Maintain context across multiple turns:

```lua
local agent = luagent.Agent.new({
  model = "gpt-4o-mini",
  system_prompt = "You are a helpful tutor."
})

-- First message
local result1 = agent:run("What is a prime number?")

-- Continue conversation with history
local result2 = agent:run("Can you give me an example?", {
  message_history = {
    { role = "user", content = "What is a prime number?" },
    { role = "assistant", content = result1.data }
  }
})
```

## API Reference

### Agent.new(config)

Create a new agent.

**Parameters:**

- `config.model` (string, required): Model identifier (e.g., "gpt-4", "gpt-4o-mini")
- `config.system_prompt` (string|function, optional): Static string or function returning prompt
- `config.output_schema` (table, optional): JSON schema for structured output validation
- `config.tools` (table, optional): Map of tool name to tool configuration
- `config.base_url` (string, optional): API base URL (default: "https://api.openai.com/v1")
- `config.api_key` (string, optional): API key (default: `OPENAI_API_KEY` env var)
- `config.temperature` (number, optional): Sampling temperature
- `config.max_tokens` (number, optional): Maximum tokens in response
- `config.http_client` (table, optional): Custom HTTP client (for testing)

**Returns:** Agent instance

### agent:run(prompt, options)

Run the agent with a prompt.

**Parameters:**

- `prompt` (string, required): The user's input message
- `options.deps` (table, optional): Dependencies to inject into context
- `options.message_history` (table, optional): Previous conversation messages
- `options.max_iterations` (number, optional): Max tool calling iterations (default: 10)

**Returns:** Result table with:
- `data`: The response (string or structured data if output_schema is set)
- `messages`: Full conversation history including tool calls
- `raw_response`: Raw API response

### RunContext

Passed to dynamic prompts and tool functions.

**Properties:**
- `deps`: Dependencies injected via `run()` options
- `messages`: Conversation message history

### Tool Configuration

Tools are defined in the `tools` table passed to `Agent.new()`:

```lua
tools = {
  tool_name = {
    description = "What the tool does",
    parameters = {
      -- JSON schema for tool parameters
      type = "object",
      properties = { ... }
    },
    func = function(ctx, args)
      -- ctx: RunContext
      -- args: Validated parameters
      return result  -- Will be JSON-encoded
    end
  }
}
```

## Compatible APIs

luagent works with any OpenAI-compatible API:

### OpenAI (default)

```lua
local agent = luagent.Agent.new({
  model = "gpt-4o-mini",
  api_key = os.getenv("OPENAI_API_KEY")
})
```

### Ollama (local)

```lua
local agent = luagent.Agent.new({
  model = "llama2",
  base_url = "http://localhost:11434/v1",
  api_key = "not-needed"  -- Ollama doesn't require auth
})
```

### Together AI

```lua
local agent = luagent.Agent.new({
  model = "meta-llama/Llama-3-70b-chat-hf",
  base_url = "https://api.together.xyz/v1",
  api_key = os.getenv("TOGETHER_API_KEY")
})
```

### Other Providers

Any service that implements the OpenAI Chat Completions API should work. Just set the appropriate `base_url` and `api_key`.

## Testing

Run the test suite:

```bash
# Install test dependencies
luarocks install dkjson

# Run tests
eval "$(luarocks path)" && lua luagent_test.lua
```

All 20 tests should pass:

```
==================================================
Test Results:
  Passed: 20
  Failed: 0
  Total:  20
==================================================
```

## Architecture

luagent is designed to be simple and hackable:

1. **JSON Schema Validator**: Validates structured outputs against schemas
2. **RunContext**: Carries dependencies and state through the execution
3. **Agent**: Orchestrates the conversation loop with the LLM
4. **Tool Execution**: Handles function calling with error handling
5. **HTTP/JSON Abstraction**: Works with multiple library implementations

The entire implementation is ~450 lines of well-commented Lua code in a single file.

## Comparison with Pydantic AI

| Feature | Pydantic AI | luagent |
|---------|-------------|---------|
| Language | Python | Lua |
| Structured Outputs | ✅ Pydantic models | ✅ JSON schemas |
| Dynamic Prompts | ✅ Functions | ✅ Functions |
| Tool Calling | ✅ Decorators | ✅ Table config |
| Dependency Injection | ✅ Type-safe | ✅ Context-based |
| Streaming | ✅ | ❌ (future) |
| Graph Support | ✅ | ❌ (future) |
| File Size | Large framework | Single 450-line file |
| Dependencies | Many | Optional (2-3) |

## Design Philosophy

- **Portable**: One file, minimal dependencies, works anywhere Lua runs
- **Simple**: Clear code over clever tricks, easy to understand and modify
- **Functional**: Covers the 80% use case without feature bloat
- **Compatible**: Works with OpenAI and compatible APIs out of the box
- **Tested**: Comprehensive test coverage for reliability

## Limitations

Current limitations (may be addressed in future versions):

- No streaming support (single response only)
- No async/concurrent execution (Lua limitation)
- Basic JSON schema validation (subset of full spec)
- No built-in retry/rate limiting
- No conversation state management beyond manual history passing

## Contributing

This is a single-file library by design. If you want to add features:

1. Keep everything in `luagent.lua`
2. Add tests to `luagent_test.lua`
3. Update examples in `example.lua`
4. Maintain backwards compatibility
5. Keep it simple and readable

## License

MIT License - see LICENSE file for details

## See Also

- [Pydantic AI](https://ai.pydantic.dev/) - The Python library that inspired this project
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)
- [JSON Schema](https://json-schema.org/)

## Author

Created as a lightweight, portable alternative to Python agent frameworks for Lua developers who need composable AI agents without heavy dependencies.
