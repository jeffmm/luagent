# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

luagent is a portable, single-file Lua library for creating composable AI agents with structured inputs/outputs and dynamic prompts. Inspired by Pydantic AI, it's designed as a lightweight alternative for building AI agents in Lua.

Key characteristics:
- Entire library in a single file (`luagent.lua`, ~500 lines)
- Minimal dependencies (optional: dkjson, lua-requests or luasocket/luasec)
- Works with OpenAI-compatible APIs (OpenAI, Ollama, Together AI, etc.)

## Development Commands

### Running Tests
```bash
# Ensure luarocks path is set and run all tests
eval "$(luarocks path)" && lua luagent_test.lua
```

Expected output: All 20 tests should pass.

### Running Examples
```bash
# Requires OPENAI_API_KEY environment variable
export OPENAI_API_KEY="your-key-here"
eval "$(luarocks path)" && lua example.lua
```

Note: Examples are commented out by default. Uncomment specific `example1()`, `example2()`, etc. function calls to run them.

### Installing Dependencies
```bash
# Required for full functionality
luarocks install dkjson

# HTTP library (pick one)
luarocks install lua-requests
# OR
luarocks install luasocket luasec
```

## Architecture

### Core Components

1. **JSON Schema Validator** (lines 179-249 in luagent.lua)
   - Validates structured outputs against JSON schemas
   - Supports nested objects, arrays, required fields, type checking
   - Basic implementation covering common use cases

2. **RunContext** (lines 252-260)
   - Carries dependencies and message history through execution
   - Used for dependency injection pattern
   - Passed to dynamic system prompts and tool functions

3. **Agent** (lines 263-499)
   - Main orchestrator for LLM conversations
   - Handles tool calling loop with max iterations (default: 10)
   - Manages message history, system prompts, and structured outputs
   - Key methods:
     - `Agent.new(config)`: Create agent with model, prompts, tools, schemas
     - `agent:run(prompt, options)`: Execute agent with user input
     - `agent:_call_openai_api()`: Make API requests (internal)
     - `agent:_execute_tool_call()`: Run tool functions (internal)

4. **Library Detection Layer** (lines 26-156)
   - Automatically detects and uses available JSON/HTTP libraries
   - Falls back to basic implementations if none found
   - Lazy-loads HTTP libraries to avoid errors on require

### Design Patterns

**Dynamic System Prompts**: System prompts can be static strings or functions that receive RunContext and return a string. This allows runtime adaptation based on dependencies:
```lua
system_prompt = function(ctx)
  return "You are a " .. ctx.deps.role .. " assistant"
end
```

**Tool Definition**: Tools are defined with description, JSON schema parameters, and a function that receives (ctx, args):
```lua
tools = {
  tool_name = {
    description = "What the tool does",
    parameters = { type = "object", properties = {...} },
    func = function(ctx, args)
      -- ctx.deps contains injected dependencies
      return result  -- Will be JSON-encoded
    end
  }
}
```

**Dependency Injection**: Runtime dependencies are passed via `run()` options and accessed in tools/prompts via `ctx.deps`. Common pattern for passing database connections, user context, API keys, etc.

## Code Style and Constraints

### Maintaining Single-File Design
- All core functionality MUST remain in `luagent.lua`
- New features should not break the single-file portability
- Keep the library focused and avoid feature bloat

### Testing Requirements
- All new functionality must have tests in `luagent_test.lua`
- Add examples to `example.lua` for user-facing features
- Tests should work without external API calls (use mock HTTP clients)

### Backwards Compatibility
- Maintain existing API surface
- Config options should be additive (use defaults for new fields)
- Don't break existing agents or tools

### Error Handling
- Tools should return `{ error = "message" }` on failure, not throw
- Agent errors should be descriptive and include context
- API errors should include status codes and response bodies

## Important Implementation Details

### Message History Format
Messages follow OpenAI's chat format:
- `{ role = "system", content = "..." }` - System prompt
- `{ role = "user", content = "..." }` - User message
- `{ role = "assistant", content = "..." }` - Assistant response
- `{ role = "tool", tool_call_id = "...", content = "..." }` - Tool result

### Tool Calling Loop
The agent runs in a loop (max 10 iterations by default):
1. Call API with current messages
2. If response has tool_calls, execute each tool
3. Add tool results to messages and loop
4. If no tool_calls, return final response

### Structured Output
When `output_schema` is set:
- Agent uses OpenAI's `response_format` with `json_schema` type
- Response content is JSON-decoded and validated against schema
- Validation errors fail the entire run

### API Compatibility
The library expects OpenAI Chat Completions API format. When adding features:
- Check compatibility with Ollama, Together AI, and other providers
- Use standard OpenAI parameters (avoid provider-specific features)
- Test with `base_url` override

## Testing Strategy

### Unit Tests (luagent_test.lua)
- Schema validation (tests 1-6, 19)
- Agent creation and configuration (tests 7-12, 20)
- RunContext (test 13)
- Tool execution (tests 14-17)
- JSON encoding (test 18)

### Integration Testing
When adding API-dependent features, use the `http_client` injection point to mock HTTP responses:
```lua
local agent = luagent.Agent.new({
  model = "test-model",
  http_client = {
    post = function(url, headers, body)
      return 200, '{"choices":[{"message":{"content":"test"}}]}'
    end
  }
})
```

## Common Gotchas

1. **Lua Table Indexing**: Lua uses 1-based indexing. The `ipairs` iterator is for arrays, `pairs` for all keys.

2. **JSON nil vs null**: Lua's `nil` is different from JSON `null`. The JSON encoder handles this automatically.

3. **Tool Function Returns**: Tool functions should return tables that will be JSON-encoded, or strings that are already JSON.

4. **Schema Required Fields**: The `required` field in JSON schemas is an array of property names, not a boolean per-property.

5. **Lazy HTTP Loading**: HTTP libraries are lazy-loaded to avoid errors. Don't initialize `http` at module load time.

6. **API Key Sources**: API keys can come from: deps.api_key > config.api_key > OPENAI_API_KEY env var. Check all three in order.
