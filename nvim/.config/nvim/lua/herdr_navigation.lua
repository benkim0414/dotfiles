-- Pinned copy of paulbkim-dev/vim-herdr-navigation editor/nvim.lua at 7873100.
-- Local behavioral delta (from navigate.sh): resolve a usable Herdr executable
-- on every handoff; warn and return only when no executable is available.
-- setup() and the mapping loop adapt the upstream hook to this config's loader.
local M = {}

local function nav(wincmd, dir)
  local prev = vim.api.nvim_get_current_win()
  vim.cmd("wincmd " .. wincmd)
  if vim.api.nvim_get_current_win() ~= prev then
    return -- moved within Neovim
  end
  -- At a split edge: cross into the surrounding multiplexer.
  if vim.env.HERDR_PANE_ID and vim.env.HERDR_PANE_ID ~= "" then
    -- A running server can retain a path ending in " (deleted)" after an
    -- update. Resolve on every handoff instead of caching that stale path.
    local herdr = vim.env.HERDR_BIN_PATH
    if herdr == nil or herdr == "" or vim.fn.executable(herdr) ~= 1 then
      herdr = vim.fn.exepath("herdr")
    end
    if herdr == "" then
      vim.notify(
        "Herdr navigation: no executable found; put herdr on PATH or set HERDR_BIN_PATH to an executable.",
        vim.log.levels.WARN
      )
      return
    end
    -- Target this pane explicitly: `--current` resolves to the server's
    -- globally focused pane, which is not necessarily the one we are in.
    vim.fn.system({ herdr, "pane", "focus", "--direction", dir, "--pane", vim.env.HERDR_PANE_ID })
  elseif vim.env.HC_TERMINAL_ID and vim.env.HC_TERMINAL_ID ~= "" then
    vim.fn.system({ "herdr-app", "do", "pane.go", "--direction", dir })
  elseif vim.env.TMUX and vim.env.TMUX ~= "" then
    local tmux = { left = "Left", down = "Down", up = "Up", right = "Right" }
    pcall(vim.cmd, "TmuxNavigate" .. tmux[dir])
  end
end

function M.setup()
  for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
    vim.keymap.set("n", "<C-" .. key .. ">", function()
      nav(key, direction)
    end, { silent = true, noremap = true, desc = "Navigate " .. direction .. " (vim/herdr)" })
  end
end

return M
