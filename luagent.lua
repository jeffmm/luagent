--[[
  luagent.lua - A portable Lua library for creating composable AI agents

  Inspired by Pydantic AI, this library provides:
  - Structured inputs/outputs with JSON schema validation
  - Dynamic prompts (static or function-based)
  - Tool/function calling
  - OpenAI-compatible API support
  - Dependency injection pattern
  - Automatic provider detection from environment variables

  Usage:
    local luagent = require('luagent')

    -- Auto-detect provider from environment variables
    local config = luagent.detect_provider()
    if config then
      local agent = luagent.Agent.new({
        model = config.model,
        base_url = config.base_url,
        api_key = config.api_key,
      })
    end

    -- Or configure manually
    local agent = luagent.Agent.new({
      model = "gpt-4",
      system_prompt = "You are a helpful assistant",
      output_schema = {...},
      tools = {...}
    })

    local result = agent:run("Hello!", { deps = {...} })
--]]

local luagent = {}

---@class JSONLibrary
---@field encode fun(obj: any): string
---@field decode fun(str: string): any

---@class HTTPClient
---@field post fun(url: string, headers: table<string, string>, body: string): number, string

---@class JSONSchema
---@field type string
---@field properties? table<string, JSONSchema>
---@field items? JSONSchema
---@field required? string[]
---@field enum? string[]
---@field description? string
---@field additionalProperties? boolean

---@class Message
---@field role "system"|"user"|"assistant"|"tool"
---@field content? string
---@field tool_calls? ToolCall[]
---@field tool_call_id? string

---@class ToolCall
---@field id string
---@field type string
---@field function ToolCallFunction

---@class ToolCallFunction
---@field name string
---@field arguments string

---@class ToolDefinition
---@field description string
---@field parameters JSONSchema
---@field func fun(ctx: RunContext, args: table): any

---@class AgentConfig
---@field model string
---@field system_prompt? string|fun(ctx: RunContext): string
---@field output_schema? JSONSchema
---@field tools? table<string, ToolDefinition>
---@field base_url? string
---@field api_key? string
---@field temperature? number
---@field max_tokens? number
---@field http_client? HTTPClient

---@class RunOptions
---@field deps? table
---@field message_history? Message[]
---@field max_iterations? number

---@class RunResult
---@field data any
---@field messages Message[]
---@field raw_response table

-- JSON library detection (try different JSON libraries)
local json
---@return JSONLibrary
local function load_json()
	local ok, result

	-- Try dkjson first
	ok, result = pcall(require, "dkjson")
	if ok then
		return result
	end

	-- Try cjson
	ok, result = pcall(require, "cjson")
	if ok then
		return result
	end

	-- Try lunajson
	ok, result = pcall(require, "lunajson")
	if ok then
		return result
	end

	-- Fallback: simple JSON encoder/decoder
	return {
		encode = function(obj)
			local t = type(obj)
			if t == "table" then
				local is_array = #obj > 0
				local parts = {}
				if is_array then
					for i, v in ipairs(obj) do
						parts[i] = luagent._json.encode(v)
					end
					return "[" .. table.concat(parts, ",") .. "]"
				else
					for k, v in pairs(obj) do
						table.insert(parts, string.format('"%s":%s', k, luagent._json.encode(v)))
					end
					return "{" .. table.concat(parts, ",") .. "}"
				end
			elseif t == "string" then
				return string.format('"%s"', obj:gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"))
			elseif t == "number" or t == "boolean" then
				return tostring(obj)
			elseif obj == nil then
				return "null"
			end
			error("Cannot encode type: " .. t)
		end,
		decode = function(str)
			-- Simple JSON decoder - not production ready, just for fallback
			if str == "null" then
				return nil
			end
			if str == "true" then
				return true
			end
			if str == "false" then
				return false
			end
			local num = tonumber(str)
			if num then
				return num
			end
			error("JSON decode not fully implemented in fallback. Please install dkjson, cjson, or lunajson")
		end,
	}
end

json = load_json()
luagent._json = json

-- HTTP library detection
local http
---@return HTTPClient?
local function load_http()
	local ok, result

	-- Try lua-requests
	ok, result = pcall(require, "requests")
	if ok then
		return {
			post = function(url, headers, body)
				local resp = result.post({
					url = url,
					headers = headers,
					data = body,
				})
				return resp.status_code, resp.text
			end,
		}
	end

	-- Try LuaSocket with https support
	local https_ok, https_lib = pcall(require, "ssl.https")
	local http_ok, http_lib = pcall(require, "socket.http")
	if https_ok or http_ok then
		local ltn12 = require("ltn12")
		return {
			post = function(url, headers, body)
				-- Detect if URL is HTTP or HTTPS
				local is_https = url:match("^https://") ~= nil
				local lib
				if is_https and https_ok then
					lib = https_lib
				elseif not is_https and http_ok then
					lib = http_lib
				elseif https_ok then
					-- Fallback to https for http URLs if http not available
					lib = https_lib
				else
					error("Cannot make request to " .. url .. " - missing required library")
				end

				local response_body = {}
				local _, status = lib.request({
					url = url,
					method = "POST",
					headers = headers,
					source = ltn12.source.string(body),
					sink = ltn12.sink.table(response_body),
				})
				return status, table.concat(response_body)
			end,
		}
	end

	-- Return nil if no HTTP library found (will be lazy-loaded when needed)
	return nil
end

-- Lazy load HTTP (don't fail on require, only when actually making API calls)
http = nil
luagent._http = nil

---@return HTTPClient
local function get_http()
	if not http then
		http = load_http()
		if not http then
			error("No HTTP library found. Please install lua-requests or luasocket with luasec")
		end
		luagent._http = http
	end
	return http
end

-- Utility functions
---@generic T
---@param obj T
---@return T
local function deep_copy(obj)
	if type(obj) ~= "table" then
		return obj
	end
	local copy = {}
	for k, v in pairs(obj) do
		copy[k] = deep_copy(v)
	end
	return copy
end

---Detects available AI provider based on environment variables.
---Returns configuration for base_url, model, and api_key.
---Checks providers in the following order: OpenAI, xAI, Anthropic, Together AI, Groq.
---@return table? config { base_url: string, model: string, api_key: string, provider: string } or nil if no provider found
function luagent.detect_provider()
	-- Define supported providers in order of preference
	local providers = {
		{
			name = "xAI",
			env_var = "XAI_API_KEY",
			base_url = "https://api.x.ai/v1",
			model = "grok-4-fast",
		},
		{
			name = "Anthropic",
			env_var = "ANTHROPIC_API_KEY",
			base_url = "https://api.anthropic.com/v1",
			model = "claude-4-5-haiku",
		},
		{
			name = "OpenAI",
			env_var = "OPENAI_API_KEY",
			base_url = "https://api.openai.com/v1",
			model = "gpt-4o-mini",
		},
		{
			name = "Together AI",
			env_var = "TOGETHER_API_KEY",
			base_url = "https://api.together.xyz/v1",
			model = "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo",
		},
		{
			name = "Groq",
			env_var = "GROQ_API_KEY",
			base_url = "https://api.groq.com/openai/v1",
			model = "llama-3.1-8b-instant",
		},
	}

	-- Check each provider's environment variable
	for _, provider in ipairs(providers) do
		local api_key = os.getenv(provider.env_var)
		if api_key and api_key ~= "" then
			return {
				base_url = provider.base_url,
				model = provider.model,
				api_key = api_key,
				provider = provider.name,
			}
		end
	end

	-- No API key found
	return nil
end

-- JSON Schema Validator
---@param value any
---@param schema? JSONSchema
---@return boolean success
---@return string? error
local function validate_schema(value, schema)
	if not schema then
		return true, nil
	end

	local schema_type = schema.type
	local value_type = type(value)

	-- Type checking
	if schema_type == "object" and value_type ~= "table" then
		return false, "Expected object, got " .. value_type
	end

	if schema_type == "array" and value_type ~= "table" then
		return false, "Expected array, got " .. value_type
	end

	if schema_type == "string" and value_type ~= "string" then
		return false, "Expected string, got " .. value_type
	end

	if schema_type == "number" and value_type ~= "number" then
		return false, "Expected number, got " .. value_type
	end

	if schema_type == "boolean" and value_type ~= "boolean" then
		return false, "Expected boolean, got " .. value_type
	end

	-- Object properties
	if schema_type == "object" and schema.properties then
		for prop_name, prop_schema in pairs(schema.properties) do
			local prop_value = value[prop_name]

			-- Check required fields
			if schema.required then
				local is_required = false
				for _, req in ipairs(schema.required) do
					if req == prop_name then
						is_required = true
						break
					end
				end

				if is_required and prop_value == nil then
					return false, "Required property '" .. prop_name .. "' is missing"
				end
			end

			-- Validate nested properties
			if prop_value ~= nil then
				local ok, err = validate_schema(prop_value, prop_schema)
				if not ok then
					return false, "Property '" .. prop_name .. "': " .. err
				end
			end
		end
	end

	-- Array items
	if schema_type == "array" and schema.items then
		for i, item in ipairs(value) do
			local ok, err = validate_schema(item, schema.items)
			if not ok then
				return false, "Array item " .. i .. ": " .. err
			end
		end
	end

	return true, nil
end

-- RunContext class
---@class RunContext
---@field deps table
---@field messages Message[]
local RunContext = {}
RunContext.__index = RunContext

---@param deps? table
---@param messages? Message[]
---@return RunContext
function RunContext.new(deps, messages)
	local self = setmetatable({}, RunContext)
	self.deps = deps or {}
	self.messages = messages or {}
	return self
end

-- Agent class
---@class Agent
---@field model string
---@field system_prompt? string|fun(ctx: RunContext): string
---@field output_schema? JSONSchema
---@field tools table<string, ToolDefinition>
---@field base_url string
---@field api_key? string
---@field temperature? number
---@field max_tokens? number
---@field http_client? HTTPClient
---@field _tool_map table<string, ToolDefinition>
local Agent = {}
Agent.__index = Agent

---@param config AgentConfig
---@return Agent
function Agent.new(config)
	local self = setmetatable({}, Agent)

	-- Required config
	self.model = config.model or error("model is required")

	-- Optional config
	self.system_prompt = config.system_prompt
	self.output_schema = config.output_schema
	self.tools = config.tools or {}
	self.base_url = config.base_url or "https://api.openai.com/v1"
	self.api_key = config.api_key or os.getenv("OPENAI_API_KEY")
	self.temperature = config.temperature
	self.max_tokens = config.max_tokens
	self.http_client = config.http_client -- Allow injecting custom HTTP client (for testing)

	-- Internal state
	self._tool_map = {}

	-- Register tools
	for tool_name, tool_config in pairs(self.tools) do
		self:_register_tool(tool_name, tool_config)
	end

	return self
end

---@param name string
---@param config ToolDefinition
function Agent:_register_tool(name, config)
	self._tool_map[name] = {
		description = config.description or "",
		parameters = config.parameters or {},
		func = config.func or error("Tool '" .. name .. "' requires a func"),
	}
end

---@param ctx RunContext
---@return string
function Agent:_build_system_prompt(ctx)
	if type(self.system_prompt) == "function" then
		return self.system_prompt(ctx)
	else
		return self.system_prompt or ""
	end
end

---@return table[]
function Agent:_build_tools()
	local tools = {}

	for name, tool in pairs(self._tool_map) do
		table.insert(tools, {
			type = "function",
			["function"] = {
				name = name,
				description = tool.description,
				parameters = tool.parameters,
			},
		})
	end

	return tools
end

---@param messages Message[]
---@param tools table[]
---@param deps? table
---@return table
function Agent:_call_openai_api(messages, tools, deps)
	local url = self.base_url .. "/chat/completions"

	-- Build request body
	local request_body = {
		model = self.model,
		messages = messages,
	}

	if self.temperature then
		request_body.temperature = self.temperature
	end

	if self.max_tokens then
		request_body.max_tokens = self.max_tokens
	end

	if #tools > 0 then
		request_body.tools = tools
	end

	-- Add structured output if schema is provided
	if self.output_schema then
		request_body.response_format = {
			type = "json_schema",
			json_schema = {
				name = "output",
				strict = true,
				schema = self.output_schema,
			},
		}
	end

	local body_str = json.encode(request_body)

	-- Determine API key (from deps, config, or env)
	local api_key = (deps and deps.api_key) or self.api_key
	if not api_key then
		error("API key not provided. Set via config, deps, or OPENAI_API_KEY env var")
	end

	-- Make request
	local headers = {
		["Content-Type"] = "application/json",
		["Authorization"] = "Bearer " .. api_key,
		["Content-Length"] = tostring(#body_str),
	}

	local http_client = self.http_client or get_http()
	local status, response_body = http_client.post(url, headers, body_str)

	if status ~= 200 then
		error("OpenAI API error (status " .. status .. "): " .. response_body)
	end

	return json.decode(response_body)
end

---@param tool_call ToolCall
---@param ctx RunContext
---@return string
function Agent:_execute_tool_call(tool_call, ctx)
	local tool_name = tool_call["function"].name
	local tool_args_str = tool_call["function"].arguments
	local tool_args = json.decode(tool_args_str)

	local tool = self._tool_map[tool_name]
	if not tool then
		return json.encode({ error = "Tool '" .. tool_name .. "' not found" })
	end

	-- Execute tool function
	local ok, result = pcall(tool.func, ctx, tool_args)

	if not ok then
		return json.encode({ error = "Tool execution failed: " .. tostring(result) })
	end

	-- Encode result as JSON
	if type(result) == "string" then
		return result
	else
		return json.encode(result)
	end
end

---@param prompt string
---@param options? RunOptions
---@return RunResult
function Agent:run(prompt, options)
	options = options or {}
	local deps = options.deps or {}
	local message_history = options.message_history or {}

	-- Create run context
	local ctx = RunContext.new(deps, {})

	-- Build messages
	local messages = deep_copy(message_history)

	-- Add system prompt
	local system_prompt = self:_build_system_prompt(ctx)
	if system_prompt and system_prompt ~= "" then
		table.insert(messages, 1, {
			role = "system",
			content = system_prompt,
		})
	end

	-- Add user prompt
	table.insert(messages, {
		role = "user",
		content = prompt,
	})

	-- Build tools
	local tools = self:_build_tools()

	-- Main agent loop (handle tool calls)
	local max_iterations = options.max_iterations or 10
	local iteration = 0

	while iteration < max_iterations do
		iteration = iteration + 1

		-- Call OpenAI API
		local response = self:_call_openai_api(messages, tools, deps)

		local choice = response.choices[1]
		local message = choice.message

		-- Add assistant message to history
		table.insert(messages, message)

		-- Check if there are tool calls
		if message.tool_calls then
			-- Execute each tool call
			for _, tool_call in ipairs(message.tool_calls) do
				local result = self:_execute_tool_call(tool_call, ctx)

				-- Add tool result to messages
				table.insert(messages, {
					role = "tool",
					tool_call_id = tool_call.id,
					content = result,
				})
			end

		-- Continue loop to get next response
		else
			-- No more tool calls, we're done
			local content = message.content

			-- Parse structured output if schema is provided
			if self.output_schema and content then
				local parsed = json.decode(content)

				-- Validate against schema
				local ok, err = validate_schema(parsed, self.output_schema)
				if not ok then
					error("Output validation failed: " .. err)
				end

				return {
					data = parsed,
					messages = messages,
					raw_response = response,
				}
			else
				return {
					data = content,
					messages = messages,
					raw_response = response,
				}
			end
		end
	end

	error("Max iterations (" .. max_iterations .. ") reached")
end

-- Export
luagent.Agent = Agent
luagent.RunContext = RunContext
luagent.validate_schema = validate_schema

return luagent
