require'parser/ParseLua'
local util = require'parser/Util'

local function debug_printf(...)
--[[
	util.printf(...)
	-- ]]
end

--
-- FormatIdentity.lua
--
-- Returns the exact source code that was used to create an AST, preserving all
-- comments and whitespace.
-- This can be used to get back a Lua source after renaming some variables in
-- an AST.
--

local function Format_Identity(ast)
	local out = {
		rope = {},  -- List of strings
		line = 1,
		char = 1,

		appendStr = function(self, str)
			table.insert(self.rope, str)

			local lines = util.splitLines(str)
			if #lines == 1 then
				self.char = self.char + #str
			else
				self.line = self.line + #lines - 1
				local lastLine = lines[#lines]
				self.char = #lastLine
			end
		end,

		appendToken = function(self, token, no_whitespace)
			if not no_whitespace then
				self:appendWhite(token)
			end
			--[*[
			debug_printf("appendToken(%q)", util.PrintTable(token))
			local data  = token.Data
			local lines = util.splitLines(data)
			while self.line + #lines < token.Line do
				print("Inserting extra line at before line "..token.Line)
				self:appendStr("\n")
				-- self.line = self.line + 1
				-- self.char = 1
			end
			--]]
			self:appendStr(token.Data)
		end,

		appendTokens = function(self, tokens, no_whitespace)
			for _,token in ipairs(tokens) do
				self:appendToken( token, no_whitespace)
			end
		end,

		appendWhite = function(self, token)
			if token.LeadingWhite then
				self:appendTokens( token.LeadingWhite )
				--self.str = self.str .. ' '
			end
		end
	}

	local formatStatlist, formatExpr;

	--patch pico8 operators like \ and bitwise ops
	local patch_binary_ops=
	{
		['\\'] = {' flr(', '/', ')'},
		['&'] = {' band(', ',', ')'},
		['|'] = {' bor(', ',', ')'},
		['^^'] = {' bxor(', ',', ')'},
		['~'] = {' bxor(', ',', ')'},
		['<<'] = {' shl(', ',', ')'},
		['>>'] = {' shr(', ',', ')'},
		['>>>'] = {' lshr(', ',', ')'},
		['<<>'] = {' rotl(', ',', ')'},
		['>><'] = {' rotr(', ',', ')'},
	}

	local patch_unary_ops={
		['~'] = {' bnot(', ')'},
		['@'] = {' peek(', ')'},
		['%'] = {' peek2(', ')'},
		['$'] = {' peek4(', ')'}
	}

	--replace pico8 glyphs in global name with a specific string
	local function patch_local_varname(name)
		--make sure to discard other returns of gsub
		local patched = name:gsub("[\127-\255]",
			function (m) return ("__glyph_%d"):format(string.byte(m))
		end)
		return patched
	end

	formatExpr = function(expr, no_leading_white)
		local tok_it = 1
		local function appendNextToken(str, no_whitespace)
			local tok = expr.Tokens[tok_it];
			if str and tok.Data ~= str then
				error("Expected token '" .. str .. "'. Tokens: " .. util.PrintTable(expr.Tokens))
			end
			out:appendToken( tok , no_whitespace)
			tok_it = tok_it + 1
		end
		local function appendToken(token, no_whitespace)
			out:appendToken( token , no_whitespace)
			tok_it = tok_it + 1
		end
		local function appendWhite()
			local tok = expr.Tokens[tok_it];
			if not tok then error(util.PrintTable(expr)) end
			out:appendWhite( tok )
			tok_it = tok_it + 1
		end
		local function appendStr(str, no_whitespace)
			if not no_whitespace then
				appendWhite()
			else
				tok_it = tok_it + 1
			end
			out:appendStr(str)
		end
		local function peek()
			if tok_it < #expr.Tokens then
				return expr.Tokens[tok_it].Data
			end
		end
		local function appendComma(mandatory, seperators)
			if true then
				seperators = seperators or { "," }
				seperators = util.lookupify( seperators )
				if not mandatory and not seperators[peek()] then
					return
				end
				assert(seperators[peek()], "Missing comma or semicolon")
				appendNextToken()
			else
				local p = peek()
				if p == "," or p == ";" then
					appendNextToken()
				end
			end
		end

		debug_printf("formatExpr(%s) at line %i", expr.AstType, expr.Tokens[1] and expr.Tokens[1].Line or -1)

		if expr.AstType == 'VarExpr' then
			-- 4 options for variable names:
			-- 1. global name without glyps -> _ENV.name
			-- 2. global name with glyphs -> _ENV['name']
			-- 3. local name with no glyphs -> name
			-- 4. local name with glyphs -> replace each glyph with __glyph_i where i is the number of glyph
			--
			-- these are done to support variables with glyphs as much as possible like pico8, and support lua 5.2 style _ENV
			if expr.Variable then
				local has_glyph = expr.Variable.Name:match("^[%w_]*$")
				if expr.Variable.IsGlobal and expr.Variable.Name ~="_ENV" then
				  -- variable name without glyphs
					if has_glyph then
						appendStr( "_ENV."..expr.Variable.Name , no_leading_white)
					else
						appendStr(("_ENV['%s']"):format(expr.Variable.Name), no_leading_white)
					end
				else
					appendStr(patch_local_varname(expr.Variable.Name), no_leading_white)
				end
			else
				appendStr( expr.Name , no_leading_white)
			end

		elseif expr.AstType == 'NumberExpr' then
			-- patch pico8 fractional binary literals to hex literals
			local value = expr.Value.Data
			if (value:sub(1,2) == '0b' or value:sub(1,2) == '0B') and value:match('.') then
				local int, frac = value:sub(3):match("([01]*)%.?([01]*)")

				--only patch fractional binary literas
				if frac ~= "" then
					--pad frac to a multiple of 4 digits
					frac = frac..string.rep('0',(-#frac)%4)
					value = ("0x%x.%x"):format(tonumber(int,2),tonumber(frac,2))
				end

			end


			appendStr( value , no_leading_white)

		elseif expr.AstType == 'StringExpr' then
			appendToken( expr.Value , no_leading_white)

		elseif expr.AstType == 'BooleanExpr' then
			appendNextToken( expr.Value and "true" or "false" , no_leading_white)

		elseif expr.AstType == 'NilExpr' then
			appendNextToken( "nil" , no_leading_white)

		elseif expr.AstType == 'BinopExpr' then
			-- patch pico8 operations like x\y to flr(x/y)
			local patch = patch_binary_ops[expr.Op] or {"", expr.Op, ""}
			out:appendStr(patch[1])
			formatExpr(expr.Lhs, no_leading_white)
			appendStr(patch[2])
			formatExpr(expr.Rhs)
			out:appendStr(patch[3])
		elseif expr.AstType == 'UnopExpr' then
			local patch = patch_unary_ops[expr.Op] or {expr.Op, ""}
			appendStr( patch[1] , no_leading_white)
			formatExpr(expr.Rhs)
			out:appendStr(patch[2])

		elseif expr.AstType == 'DotsExpr' then
			appendNextToken( "..." , no_leading_white)

		elseif expr.AstType == 'CallExpr' then
			formatExpr(expr.Base, no_leading_white)
			appendNextToken( "(" )
			for i,arg in ipairs( expr.Arguments ) do
				formatExpr(arg)
				appendComma( i ~= #expr.Arguments )
			end
			appendNextToken( ")" )

		elseif expr.AstType == 'TableCallExpr' then
			formatExpr( expr.Base , no_leading_white)
			formatExpr( expr.Arguments[1] )

		elseif expr.AstType == 'StringCallExpr' then
			formatExpr(expr.Base, no_leading_white)
			appendToken( expr.Arguments[1] )

		elseif expr.AstType == 'IndexExpr' then
			formatExpr(expr.Base, no_leading_white)
			appendNextToken( "[" )
			formatExpr(expr.Index)
			appendNextToken( "]" )

		elseif expr.AstType == 'MemberExpr' then
			formatExpr(expr.Base, no_leading_white)
			if expr.Ident.Data:match("^[%w_]*$") then
				appendNextToken()  -- . or :
				appendToken(expr.Ident)
			else
				-- add support for pico8 glyphs as table keys
				-- use non expanded [] syntax for .
				-- no support for :
				if peek() ~= '.' then
					error(": syntax not for variables with glyphs")
				end
				appendWhite()
				out:appendStr("['")
				appendToken(expr.Ident)
				out:appendStr("']")
			end

		elseif expr.AstType == 'Function' then
			-- anonymous function
			appendNextToken( "function" , no_leading_white)
			appendNextToken( "(" )
			if #expr.Arguments > 0 then
				for i = 1, #expr.Arguments do
					appendStr( patch_local_varname(expr.Arguments[i].Name ))
					if i ~= #expr.Arguments then
						appendNextToken(",")
					elseif expr.VarArg then
						appendNextToken(",")
						appendNextToken("...")
					end
				end
			elseif expr.VarArg then
				appendNextToken("...")
			end
			appendNextToken(")")
			formatStatlist(expr.Body)
			appendNextToken("end")

		elseif expr.AstType == 'ConstructorExpr' then
			appendNextToken( "{" , no_leading_white)
			for i = 1, #expr.EntryList do
				local entry = expr.EntryList[i]
				if entry.Type == 'Key' then
					appendNextToken( "[" )
					formatExpr(entry.Key)
					appendNextToken( "]" )
					appendNextToken( "=" )
					formatExpr(entry.Value)
				elseif entry.Type == 'Value' then
					formatExpr(entry.Value)
				elseif entry.Type == 'KeyString' then
					appendStr(patch_local_varname(entry.Key))
					appendNextToken( "=" )
					formatExpr(entry.Value)
				end
				appendComma( i ~= #expr.EntryList, { ",", ";" } )
			end
			appendNextToken( "}" )

		elseif expr.AstType == 'Parentheses' then
			appendNextToken( "(" , no_leading_white)
			formatExpr(expr.Inner)
			appendNextToken( ")" )

		else
			print("Unknown AST Type: ", statement.AstType)
		end

		assert(tok_it == #expr.Tokens + 1)
		debug_printf("/formatExpr")
	end


	local formatStatement = function(statement)
		local tok_it = 1
		local function appendNextToken(str)
			local tok = statement.Tokens[tok_it];
			assert(tok, string.format("Not enough tokens for %q. First token at %i:%i",
				str, statement.Tokens[1].Line, statement.Tokens[1].Char))
			assert(tok.Data == str,
				string.format('Expected token %q, got %q', str, tok.Data))
			out:appendToken( tok )
			tok_it = tok_it + 1
		end
		local function appendToken(token)
			out:appendToken( str )
			tok_it = tok_it + 1
		end
		local function appendWhite()
			local tok = statement.Tokens[tok_it];
			out:appendWhite( tok )
			tok_it = tok_it + 1
		end
		local function appendStr(str)
			appendWhite()
			out:appendStr(str)
		end
		local function appendComma(mandatory)
			if mandatory
			   or (tok_it < #statement.Tokens and statement.Tokens[tok_it].Data == ",") then
			   appendNextToken( "," )
			end
		end

		debug_printf("")
		debug_printf(string.format("formatStatement(%s) at line %i", statement.AstType, statement.Tokens[1] and statement.Tokens[1].Line or -1))

		if statement.AstType == 'AssignmentStatement' then
			for i,v in ipairs(statement.Lhs) do
				formatExpr(v)
				appendComma( i ~= #statement.Lhs )
			end
			if #statement.Rhs > 0 then
				--patch pico8 compound operators
				--a,b += exp1, exp2 - > a,b = b + (exp1), exp2
				local compound = statement.Operator ~= ""
				if not compound then
					appendNextToken( "=" )
				else
					appendWhite()
					out:appendStr("=")
				end
				for i,v in ipairs(statement.Rhs) do
					if i == 1 and compound then
						-- patch pico8 operations like x\=y to x=flr(x\(y))
						local patch = patch_binary_ops[statement.Operator] or {"", statement.Operator, ""}
						out:appendStr(patch[1])
						formatExpr(statement.Lhs[#statement.Lhs], true)
						out:appendStr(patch[2])
						out:appendStr("(")
						formatExpr(v)
						out:appendStr(")")
						out:appendStr(patch[3])
					else
						formatExpr(v)
					end
					appendComma( i ~= #statement.Rhs )
				end
			end

		elseif statement.AstType == 'CallStatement' then
			formatExpr(statement.Expression)

		elseif statement.AstType == 'LocalStatement' then
			appendNextToken( "local" )
			for i = 1, #statement.LocalList do
				appendStr( patch_local_varname(statement.LocalList[i].Name ))
				appendComma( i ~= #statement.LocalList )
			end
			if #statement.InitList > 0 then
				local compound = statement.Operator ~= ""
				if not compound then
					appendNextToken( "=" )
				else
					appendWhite()
					out:appendStr("=")
				end

				for i = 1, #statement.InitList do
					if i == 1 and compound then

						local patch = patch_binary_ops[statement.Operator] or {"", statement.Operator, ""}
						out:appendStr(patch[1])
						out:appendStr(patch_local_varname(statement.LocalList[#statement.LocalList].Name))
						out:appendStr(patch[2])
						out:appendStr("(")
						formatExpr(statement.InitList[i])
						out:appendStr(")")
						out:appendStr(patch[3])

					else
						formatExpr(statement.InitList[i])
					end
					appendComma( i ~= #statement.InitList )
				end
			end

		elseif statement.AstType == 'IfStatement' then
			-- add then and end to pico8 shorthand if
			appendNextToken( "if" )
			formatExpr( statement.Clauses[1].Condition )
			if statement.shorthand then
				out:appendStr(" then ")
			else
			 appendNextToken( "then" )
			end
			formatStatlist( statement.Clauses[1].Body )
			for i = 2, #statement.Clauses do
				local st = statement.Clauses[i]
				if st.Condition then
					appendNextToken( "elseif" )
					formatExpr(st.Condition)
					appendNextToken( "then" )
				else
					appendNextToken( "else" )
				end
				formatStatlist(st.Body)
			end
			if statement.shorthand then
				out:appendStr(" end ")
			else
				appendNextToken( "end" )
			end

		elseif statement.AstType == 'WhileStatement' then
			appendNextToken( "while" )
			formatExpr(statement.Condition)
			if not statement.shorthand then
				appendNextToken( "do" )
				formatStatlist(statement.Body)
				appendNextToken( "end" )
			else
				-- add do and end to pico8 shorthand if
				out:appendStr( " do " )
				formatStatlist(statement.Body)
				out:appendStr( " end " )
			end

		elseif statement.AstType == 'DoStatement' then
			appendNextToken( "do" )
			formatStatlist(statement.Body)
			appendNextToken( "end" )

		elseif statement.AstType == 'ReturnStatement' then
			appendNextToken( "return" )
			for i = 1, #statement.Arguments do
				formatExpr(statement.Arguments[i])
				appendComma( i ~= #statement.Arguments )
			end

		elseif statement.AstType == 'BreakStatement' then
			appendNextToken( "break" )

		elseif statement.AstType == 'RepeatStatement' then
			appendNextToken( "repeat" )
			formatStatlist(statement.Body)
			appendNextToken( "until" )
			formatExpr(statement.Condition)

		elseif statement.AstType == 'Function' then
			--print(util.PrintTable(statement))

			if statement.IsLocal then
				appendNextToken( "local" )
			end
			appendNextToken( "function" )

			if statement.IsLocal then
				appendStr(patch_local_varname(statement.Name.Name))
			else
				formatExpr(statement.Name)
			end

			appendNextToken( "(" )
			if #statement.Arguments > 0 then
				for i = 1, #statement.Arguments do
					appendStr( patch_local_varname(statement.Arguments[i].Name ))
					appendComma( i ~= #statement.Arguments or statement.VarArg )
					if i == #statement.Arguments and statement.VarArg then
						appendNextToken( "..." )
					end
				end
			elseif statement.VarArg then
				appendNextToken( "..." )
			end
			appendNextToken( ")" )

			formatStatlist(statement.Body)
			appendNextToken( "end" )

		elseif statement.AstType == 'GenericForStatement' then
			appendNextToken( "for" )
			for i = 1, #statement.VariableList do
				appendStr( patch_local_varname(statement.VariableList[i].Name ))
				appendComma( i ~= #statement.VariableList )
			end
			appendNextToken( "in" )
			for i = 1, #statement.Generators do
				formatExpr(statement.Generators[i])
				appendComma( i ~= #statement.Generators )
			end
			appendNextToken( "do" )
			formatStatlist(statement.Body)
			appendNextToken( "end" )

		elseif statement.AstType == 'NumericForStatement' then
			appendNextToken( "for" )
			appendStr(patch_local_varname( statement.Variable.Name ))
			appendNextToken( "=" )
			formatExpr(statement.Start)
			appendNextToken( "," )
			formatExpr(statement.End)
			if statement.Step then
				appendNextToken( "," )
				formatExpr(statement.Step)
			end
			appendNextToken( "do" )
			formatStatlist(statement.Body)
			appendNextToken( "end" )

		elseif statement.AstType == 'LabelStatement' then
			appendNextToken( "::" )
			appendStr( patch_local_varname(statement.Label ))
			appendNextToken( "::" )

		elseif statement.AstType == 'GotoStatement' then
			appendNextToken( "goto" )
			appendStr( patch_local_varname(statement.Label ))

		elseif statement.AstType == 'PrintStatement' then
			appendStr("print(")
			for i, arg in ipairs(statement.Arguments) do
				formatExpr(arg)
				appendComma(i ~= #statement.Arguments)
			end
			out:appendStr(")")
		elseif statement.AstType == 'Eof' then
			appendWhite()

		else
			print("Unknown AST Type: ", statement.AstType)
		end

		if statement.Semicolon then
			appendNextToken(";")
		end

		assert(tok_it == #statement.Tokens + 1)
		debug_printf("/formatStatment")
	end

	formatStatlist = function(statList)
		for _, stat in ipairs(statList.Body) do
			formatStatement(stat)
		end
	end

	formatStatlist(ast)

	return true, table.concat(out.rope)
end

return Format_Identity
