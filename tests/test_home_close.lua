-- Minimal self-check for Notes Home's `q` / M.close behavior.
-- Covers the last-window regression (E444: Cannot close last window).
-- Run with: lua tests/test_home_close.lua

-- Resolve the repo root from this script's path so the module can be required
-- regardless of the working directory.
local script = (arg and arg[0]) or "tests/test_home_close.lua"
local repo_dir = script:match("^(.*)/tests/[^/]+$") or "."
package.path = repo_dir .. "/lua/?.lua;" .. package.path

local tests = 0
local passed = 0

local function check(ok, msg)
	tests = tests + 1
	if ok then
		passed = passed + 1
	else
		io.stderr:write("FAIL: " .. msg .. "\n")
	end
end

-- ── vim stub ──────────────────────────────────────────────────────────

local calls
local function reset(windows)
	calls = {
		winnr_args = {},
		option_writes = {},
		closed_wins = {},
		cmds = {},
		current_win = 42,
		current_buf = 7,
	}
	_G.vim = {
		fn = {
			winnr = function(what)
				table.insert(calls.winnr_args, what)
				return windows
			end,
		},
		cmd = function(str)
			table.insert(calls.cmds, str)
		end,
		api = {
			nvim_get_current_buf = function()
				return calls.current_buf
			end,
			nvim_get_current_win = function()
				return calls.current_win
			end,
			nvim_set_option_value = function(name, value, opts)
				table.insert(calls.option_writes, { name = name, value = value, opts = opts })
			end,
			nvim_win_close = function(win, force)
				table.insert(calls.closed_wins, { win = win, force = force })
			end,
		},
	}
end

reset(1) -- install the stub before the module is loaded
local home = require("notes.home")

-- 1. Last window (winnr("$") == 1): clear bufhidden, :enew, never close.
reset(1)
home.close(99)
check(#calls.winnr_args == 1 and calls.winnr_args[1] == "$", "last window: winnr('$') consulted")
check(#calls.cmds == 1 and calls.cmds[1] == "enew", "last window: :enew invoked")
check(#calls.option_writes == 1, "last window: exactly one option written")
if #calls.option_writes == 1 then
	local w = calls.option_writes[1]
	check(w.name == "bufhidden", "last window: writes bufhidden")
	check(w.value == "", "last window: bufhidden cleared")
	check(w.opts.buf == 99, "last window: targets the passed buffer")
end
check(#calls.closed_wins == 0, "last window: no window closed")

-- 2. Not the last window: force-close the current window, leave bufhidden alone.
reset(3)
home.close(99)
check(#calls.closed_wins == 1, "multi window: one window closed")
if #calls.closed_wins == 1 then
	check(calls.closed_wins[1].win == 42, "multi window: closes the current window")
	check(calls.closed_wins[1].force == true, "multi window: close is forced")
end
check(#calls.cmds == 0, "multi window: no :enew")
check(#calls.option_writes == 0, "multi window: bufhidden untouched")

-- 3. The buffer argument is optional and defaults to the current buffer.
reset(1)
home.close()
check(#calls.option_writes == 1 and calls.option_writes[1].opts.buf == 7, "default buffer is the current buffer")

io.write(string.format("\n%d / %d checks passed\n", passed, tests))
if passed ~= tests then
	io.write("SOME CHECKS FAILED\n")
	os.exit(1)
else
	io.write("ALL CHECKS PASSED\n")
	os.exit(0)
end
