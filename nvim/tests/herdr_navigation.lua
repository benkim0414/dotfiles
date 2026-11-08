-- Run from the task worktree: nvim --headless -u NONE -i NONE -l nvim/tests/herdr_navigation.lua
local root = vim.fn.getcwd() .. "/nvim/.config/nvim"
package.path = root .. "/lua/?.lua;" .. package.path
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary .. "/bin", "p")
local warnings, calls = {}, {}
vim.notify = function(message) warnings[#warnings + 1] = message end

local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect({ actual = actual, expected = expected }))
end

local function mock(path, label, status)
  vim.fn.writefile({ "#!/bin/sh", "printf '%s\\n' '" .. label .. "' \"$@\"", "exit " .. (status or 0) }, path)
  assert(vim.fn.setfperm(path, "rwx------") == 1)
end

local system = vim.fn.system
vim.fn.system = function(arguments)
  calls[#calls + 1] = arguments
  return system(arguments)
end

local function press(key)
  local mapping = vim.fn.maparg("<C-" .. key .. ">", "n", false, true)
  assert(type(mapping.callback) == "function")
  mapping.callback()
end

local function run()
  mock(temporary .. "/bin/herdr", "fallback")
  mock(temporary .. "/bin/herdr-app", "desktop")
  mock(temporary .. "/explicit herdr", "explicit")
  vim.fn.writefile({ "not executable" }, temporary .. "/not-executable")
  vim.env.PATH = temporary .. "/bin"
  vim.env.HERDR_PANE_ID = "test:pane"
  vim.env.HERDR_BIN_PATH = temporary .. "/explicit herdr"
  vim.env.TMUX = "test"
  vim.env.HC_TERMINAL_ID = "desktop-test"

  -- Exercise the actual plugin configuration, including suppression of tmux mappings.
  local specs = dofile(root .. "/lua/plugins/nav.lua")
  local navigator = specs[#specs]
  navigator.init()
  navigator.config()
  equal(vim.g.tmux_navigator_no_mappings, 1)
  equal(vim.fn.maparg("<C-\\>", "n"), "<Cmd>TmuxNavigatePrevious<CR>")

  for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
    press(key)
    equal(calls[#calls], { temporary .. "/explicit herdr", "pane", "focus", "--direction", direction, "--pane", "test:pane" })
  end
  -- A later update can invalidate the same path after setup and successful use.
  equal(vim.fn.delete(temporary .. "/explicit herdr"), 0)
  press("h")
  equal(calls[#calls][1], temporary .. "/bin/herdr")
  for _, path in ipairs({ "", temporary .. "/missing", temporary .. "/herdr (deleted)", temporary .. "/not-executable" }) do
    vim.env.HERDR_BIN_PATH = path
    press("h")
    equal(calls[#calls][1], temporary .. "/bin/herdr")
  end
  vim.env.HERDR_BIN_PATH = nil
  press("l")
  equal(calls[#calls][1], temporary .. "/bin/herdr")
  equal(#warnings, 0)

  -- Each internal split movement must succeed even when no binary is available.
  vim.env.PATH = temporary
  local count = #calls
  for _, pair in ipairs({ { "vsplit", "h" }, { "vsplit", "l" }, { "split", "j" }, { "split", "k" } }) do
    vim.cmd("only")
    vim.cmd(pair[1])
    local opposite = ({ h = "l", l = "h", j = "k", k = "j" })[pair[2]]
    vim.cmd("wincmd " .. opposite)
    local previous = vim.api.nvim_get_current_win()
    press(pair[2])
    assert(vim.api.nvim_get_current_win() ~= previous)
  end
  equal(#calls, count)
  equal(#warnings, 0)
  vim.cmd("only")
  press("h")
  equal(#calls, count)
  equal(#warnings, 1)
  assert(warnings[1]:find("no executable found", 1, true))

  vim.env.HERDR_BIN_PATH = temporary .. "/explicit herdr"
  mock(vim.env.HERDR_BIN_PATH, "failure", 7)
  press("h")
  equal(vim.v.shell_error, 7)
  equal(#warnings, 1) -- Only the missing-binary path warns; launched commands stay quiet.

  -- Desktop handoff precedes tmux when there is no TUI pane.
  vim.env.PATH = temporary .. "/bin"
  vim.env.HERDR_PANE_ID = ""
  for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
    press(key)
    equal(calls[#calls], { "herdr-app", "do", "pane.go", "--direction", direction })
  end
  vim.env.HC_TERMINAL_ID = ""
  vim.fn.system = function() error("unexpected external command") end

  vim.env.HERDR_PANE_ID = ""
  local tmux_calls = {}
  for _, direction in ipairs({ "Left", "Down", "Up", "Right" }) do
    vim.api.nvim_create_user_command("TmuxNavigate" .. direction, function()
      tmux_calls[#tmux_calls + 1] = direction
    end, {})
  end
  vim.env.TMUX = "test"
  for _, key in ipairs({ "h", "j", "k", "l" }) do press(key) end
  equal(tmux_calls, { "Left", "Down", "Up", "Right" })
  vim.env.TMUX = ""
  for _, key in ipairs({ "h", "j", "k", "l" }) do press(key) end
  equal(#tmux_calls, 4)
  equal(#warnings, 1)
end

local ok, err = xpcall(run, debug.traceback)
vim.fn.system = system
vim.fn.delete(temporary, "rf")
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
end
print("PASS: Herdr navigation mappings, executable fallback, missing-binary warning, quiet exits, splits, desktop, and tmux fallback")
