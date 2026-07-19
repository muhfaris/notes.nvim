local M = {}

local ns = vim.api.nvim_create_namespace("notes/tablemath")

-- Utility: Convert Excel-style column string to 1-based index (e.g. A->1, B->2, Z->26, AA->27)
local function col_to_num(col_str)
	col_str = col_str:upper()
	local num = 0
	for i = 1, #col_str do
		num = num * 26 + (col_str:byte(i) - 64)
	end
	return num
end

-- Utility: Convert 1-based index to Excel-style column string (e.g. 1->A, 2->B)
local function num_to_col(num)
	local col = ""
	while num > 0 do
		local mod = (num - 1) % 26
		col = string.char(65 + mod) .. col
		num = math.floor((num - mod) / 26)
	end
	return col
end

-- Utility: Split table row by | and trim whitespaces from cell values
local function split_row(line)
	local s = line:gsub("^%s*|", ""):gsub("|%s*$", "")
	local cells = {}
	local last_pos = 1
	while true do
		local start_pos, end_pos = string.find(s, "|", last_pos)
		if not start_pos then
			table.insert(cells, vim.trim(string.sub(s, last_pos)))
			break
		end
		table.insert(cells, vim.trim(string.sub(s, last_pos, start_pos - 1)))
		last_pos = end_pos + 1
	end
	return cells
end

-- Lexer/Tokenizer for formula strings
local function tokenize(expr_str)
	local tokens = {}
	local i = 1
	while i <= #expr_str do
		local char = expr_str:sub(i, i)
		if char:match("%s") then
			i = i + 1
		elseif char == "(" then
			table.insert(tokens, { type = "LPAREN", val = "(" })
			i = i + 1
		elseif char == ")" then
			table.insert(tokens, { type = "RPAREN", val = ")" })
			i = i + 1
		elseif char == "+" or char == "-" or char == "*" or char == "/" then
			table.insert(tokens, { type = "OP", val = char })
			i = i + 1
		elseif expr_str:sub(i):match("^%a+%d*:%a+%d*") then
			local range = expr_str:sub(i):match("^%a+%d*:%a+%d*")
			table.insert(tokens, { type = "RANGE", val = range })
			i = i + #range
		elseif expr_str:sub(i):match("^%a+%d+") then
			local ref = expr_str:sub(i):match("^%a+%d+")
			table.insert(tokens, { type = "CELL", val = ref })
			i = i + #ref
		elseif expr_str:sub(i):match("^%a+") then
			local name = expr_str:sub(i):match("^%a+")
			table.insert(tokens, { type = "FUNC", val = name:upper() })
			i = i + #name
		elseif expr_str:sub(i):match("^%d+%.?%d*") then
			local num = expr_str:sub(i):match("^%d+%.?%d*")
			table.insert(tokens, { type = "NUM", val = tonumber(num) })
			i = i + #num
		else
			error("Unknown token at: " .. char, 0)
		end
	end
	table.insert(tokens, { type = "EOF" })
	return tokens
end

-- Recursive descent parser
local function parse(tokens)
	local idx = 1

	local function peek()
		return tokens[idx]
	end

	local function consume(type)
		local t = peek()
		if type and t.type ~= type then
			error(string.format("Expected token %s, got %s", type, t.type), 0)
		end
		idx = idx + 1
		return t
	end

	local expression -- forward declaration

	local function factor()
		local t = peek()
		if t.type == "NUM" then
			consume()
			return { type = "NUM", val = t.val }
		elseif t.type == "CELL" then
			consume()
			return { type = "CELL", val = t.val }
		elseif t.type == "FUNC" then
			local func_name = consume().val
			consume("LPAREN")
			local arg_token = peek()
			local arg
			if arg_token.type == "RANGE" then
				arg = consume().val
			elseif arg_token.type == "CELL" then
				arg = consume().val
			else
				error("Expected RANGE or CELL in function call", 0)
			end
			consume("RPAREN")
			return { type = "FUNC", name = func_name, arg = arg }
		elseif t.type == "LPAREN" then
			consume()
			local expr = expression()
			consume("RPAREN")
			return expr
		else
			error("Unexpected token: " .. tostring(t.type), 0)
		end
	end

	local function term()
		local node = factor()
		while peek().type == "OP" and (peek().val == "*" or peek().val == "/") do
			local op = consume().val
			local right = factor()
			node = { type = "BINOP", op = op, left = node, right = right }
		end
		return node
	end

	expression = function()
		local node = term()
		while peek().type == "OP" and (peek().val == "+" or peek().val == "-") do
			local op = consume().val
			local right = term()
			node = { type = "BINOP", op = op, left = node, right = right }
		end
		return node
	end

	local ast = expression()
	if peek().type ~= "EOF" then
		error("Extra tokens after expression", 0)
	end
	return ast
end

local resolve_ref -- forward declaration

-- Evaluate AST node
local function eval_node(node, tbl, visited)
	if node.type == "NUM" then
		return node.val
	elseif node.type == "CELL" then
		local val = resolve_ref(tbl, node.val, visited)
		if type(val) == "string" then
			local num = tonumber(val)
			if not num then
				error("#VALUE!", 0)
			end
			return num
		end
		return val
	elseif node.type == "BINOP" then
		local left = eval_node(node.left, tbl, visited)
		local right = eval_node(node.right, tbl, visited)
		if node.op == "+" then
			return left + right
		elseif node.op == "-" then
			return left - right
		elseif node.op == "*" then
			return left * right
		elseif node.op == "/" then
			if right == 0 then
				error("#DIV/0!", 0)
			end
			return left / right
		end
	elseif node.type == "FUNC" then
		local values = {}
		if node.arg:find(":") then
			local start_ref, end_ref = node.arg:match("^([^:]+):([^:]+)$")
			local start_col, start_row = start_ref:match("^([A-Z]+)(%d+)$")
			local end_col, end_row = end_ref:match("^([A-Z]+)(%d+)$")

			local sc = col_to_num(start_col)
			local ec = col_to_num(end_col)
			local sr = tonumber(start_row)
			local er = tonumber(end_row)

			if sc > ec then
				sc, ec = ec, sc
			end
			if sr > er then
				sr, er = er, sr
			end

			for r = sr, er do
				for c = sc, ec do
					local col_name = num_to_col(c)
					local ref = col_name .. tostring(r)
					local ok, val = pcall(resolve_ref, tbl, ref, visited)
					if ok then
						table.insert(values, val)
					end
				end
			end
		else
			local ok, val = pcall(resolve_ref, tbl, node.arg, visited)
			if ok then
				table.insert(values, val)
			end
		end

		local num_values = {}
		for _, v in ipairs(values) do
			local n = tonumber(v)
			if n then
				table.insert(num_values, n)
			end
		end

		if node.name == "SUM" then
			local sum = 0
			for _, v in ipairs(num_values) do
				sum = sum + v
			end
			return sum
		elseif node.name == "AVG" then
			if #num_values == 0 then
				return 0
			end
			local sum = 0
			for _, v in ipairs(num_values) do
				sum = sum + v
			end
			return sum / #num_values
		elseif node.name == "COUNT" then
			return #num_values
		elseif node.name == "MIN" then
			if #num_values == 0 then
				return 0
			end
			return math.min(unpack(num_values))
		elseif node.name == "MAX" then
			if #num_values == 0 then
				return 0
			end
			return math.max(unpack(num_values))
		else
			error("Unknown function: " .. tostring(node.name), 0)
		end
	end
end

-- Evaluates formula string
local function eval_formula(expr_str, tbl, visited)
	expr_str = expr_str:upper()
	local tokens = tokenize(expr_str)
	local ast = parse(tokens)
	return eval_node(ast, tbl, visited)
end

-- Resolves reference by looking up the cell and returning its value (caching and resolving formula recursion)
resolve_ref = function(tbl, cell_ref, visited)
	if tbl.cache[cell_ref] ~= nil then
		local status, val = unpack(tbl.cache[cell_ref])
		if status then
			return val
		else
			error(val, 0)
		end
	end

	local col_part, row_part = cell_ref:match("^([A-Z]+)(%d+)$")
	if not col_part or not row_part then
		error("#VALUE!", 0)
	end

	local col_idx = col_to_num(col_part)
	local row_idx = tonumber(row_part)

	local row = tbl.rows[row_idx]
	if not row then
		tbl.cache[cell_ref] = { true, 0 }
		return 0
	end

	local cell_str = row.cells[col_idx]
	if not cell_str or cell_str == "" then
		tbl.cache[cell_ref] = { true, 0 }
		return 0
	end

	if cell_str:sub(1, 1) == "=" then
		if visited[cell_ref] then
			error("circular", 0)
		end
		visited[cell_ref] = true

		local ok, val = pcall(eval_formula, cell_str:sub(2), tbl, visited)
		visited[cell_ref] = nil

		if ok then
			tbl.cache[cell_ref] = { true, val }
			return val
		else
			tbl.cache[cell_ref] = { false, val }
			error(val, 0)
		end
	else
		tbl.cache[cell_ref] = { true, cell_str }
		return cell_str
	end
end

-- Scans note buffer and identifies valid tables
local function parse_tables(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local tables = {}
	local in_table = false
	local current_table = nil

	for i, line in ipairs(lines) do
		local has_pipe = string.find(line, "|")
		if has_pipe then
			if not in_table then
				in_table = true
				current_table = {
					start_line = i,
					raw_lines = {},
				}
			end
			table.insert(current_table.raw_lines, { line_num = i, text = line })
		else
			if in_table then
				in_table = false
				table.insert(tables, current_table)
				current_table = nil
			end
		end
	end
	if in_table and current_table then
		table.insert(tables, current_table)
	end

	local valid_tables = {}
	for _, tbl in ipairs(tables) do
		local sep_idx = nil
		for idx, row in ipairs(tbl.raw_lines) do
			local stripped = row.text:gsub("%s", "")
			if stripped:match("^|?[:%-%|]+|?$") and stripped:find("-") then
				sep_idx = idx
				break
			end
		end

		if sep_idx then
			local data_rows = {}
			for idx = sep_idx + 1, #tbl.raw_lines do
				local r = tbl.raw_lines[idx]
				table.insert(data_rows, {
					line_num = r.line_num,
					raw = r.text,
					cells = split_row(r.text),
				})
			end

			if #data_rows > 0 then
				table.insert(valid_tables, {
					start_line = tbl.start_line,
					end_line = tbl.start_line + #tbl.raw_lines - 1,
					rows = data_rows,
					cache = {},
				})
			end
		end
	end

	return valid_tables
end

-- Entry point: refreshes formula calculations and displays virtual text
M.refresh = function(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	-- Clear old extmarks
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	local ok, tbls = pcall(parse_tables, buf)
	if not ok or not tbls then
		return
	end

	for _, tbl in ipairs(tbls) do
		for row_idx, row in ipairs(tbl.rows) do
			local results = {}
			for col_idx, cell in ipairs(row.cells) do
				if cell:sub(1, 1) == "=" then
					local ref = num_to_col(col_idx) .. tostring(row_idx)
					local success, val = pcall(resolve_ref, tbl, ref, {})
					if success then
						if type(val) == "number" then
							if val == math.floor(val) then
								table.insert(results, tostring(val))
							else
								table.insert(results, string.format("%.2f", val))
							end
						else
							table.insert(results, tostring(val))
						end
					else
						table.insert(results, "⚠️ " .. tostring(val))
					end
				end
			end

			if #results > 0 then
				local virt_text = "  │ " .. table.concat(results, " │ ") .. " │"
				vim.api.nvim_buf_set_extmark(buf, ns, row.line_num - 1, 0, {
					virt_text = { { virt_text, "Comment" } },
					virt_text_pos = "eol",
					hl_mode = "combine",
				})
			end
		end
	end
end

return M
