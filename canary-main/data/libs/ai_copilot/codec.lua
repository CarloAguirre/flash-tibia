local codec = {}

local function escapeString(value)
	if value == nil then
		value = ""
	end

	value = tostring(value)
	value = value:gsub("\\", "\\\\")
	value = value:gsub('"', '\\"')
	value = value:gsub("\b", "\\b")
	value = value:gsub("\f", "\\f")
	value = value:gsub("\n", "\\n")
	value = value:gsub("\r", "\\r")
	value = value:gsub("\t", "\\t")
	return '"' .. value .. '"'
end

local function extractJsonString(buffer, key)
	local keyStart = buffer:find('"' .. key .. '"', 1, true)
	if not keyStart then
		return ""
	end

	local colon = buffer:find(":", keyStart, true)
	local valueStart = colon and buffer:find('"', colon + 1, true)
	if not valueStart then
		return ""
	end

	local value = {}
	local escaped = false
	for index = valueStart + 1, #buffer do
		local character = buffer:sub(index, index)
		if escaped then
			if character == "n" then
				value[#value + 1] = "\n"
			elseif character == "r" then
				value[#value + 1] = "\r"
			elseif character == "t" then
				value[#value + 1] = "\t"
			else
				value[#value + 1] = character
			end
			escaped = false
		elseif character == "\\" then
			escaped = true
		elseif character == '"' then
			return table.concat(value)
		else
			value[#value + 1] = character
		end
	end

	return ""
end

local function encodeValue(value)
	local valueType = type(value)
	if valueType == "string" then
		return escapeString(value)
	elseif valueType == "number" then
		return tostring(value)
	elseif valueType == "boolean" then
		return value and "true" or "false"
	elseif valueType == "table" then
		local parts = {}
		for key, childValue in pairs(value) do
			parts[#parts + 1] = escapeString(key) .. ":" .. encodeValue(childValue)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

function codec.decodeRequest(buffer)
	return {
		requestId = extractJsonString(buffer, "requestId"),
		type = extractJsonString(buffer, "type"),
		text = extractJsonString(buffer, "text"),
	}
end

function codec.encode(value)
	return encodeValue(value)
end

return codec