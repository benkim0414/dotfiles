local api = vim.api
local M = {}

local function make_keymap_fn(mode, o)
  local parent_opts = vim.deepcopy(o)
  return function(combo, mapping, opts)
    assert(combo ~= mode, string.format("The combo should not be the same as the mode for %s", combo))
    local _opts = opts and vim.deepcopy(opts) or {}

    if type(mapping) == "function" then
      local fn_id = globals._create(mapping)
      mapping = string.format("<cmd>lua globals._execute(%s)<cr>", fn_id)
    end

    if _opts.bufnr then
      local bufnr = _opts.bufnr
      _opts.bufnr = nil
      _opts = vim.tbl_extend("keep", _opts, parent_opts)
      api.nvim_buf_set_keymap(bufnr, mode, combo, mapping, _opts)
    else
      api.nvim_set_keymap(mode, combo, mapping, vim.tbl_extend("keep", _opts, parent_opts))
    end
  end
end

local map_opts = { noremap = false, silent = true }
M.map = make_keymap_fn("", map_opts)
M.nmap = make_keymap_fn("n", map_opts)
M.xmap = make_keymap_fn("x", map_opts)
M.imap = make_keymap_fn("i", map_opts)
M.vmap = make_keymap_fn("v", map_opts)
M.omap = make_keymap_fn("o", map_opts)
M.tmap = make_keymap_fn("t", map_opts)
M.smap = make_keymap_fn("s", map_opts)
M.cmap = make_keymap_fn("c", map_opts)

local noremap_opts = { noremap = true, silent = true }
M.nnoremap = make_keymap_fn("n", noremap_opts)
M.xnoremap = make_keymap_fn("x", noremap_opts)
M.vnoremap = make_keymap_fn("v", noremap_opts)
M.inoremap = make_keymap_fn("i", noremap_opts)
M.onoremap = make_keymap_fn("o", noremap_opts)
M.tnoremap = make_keymap_fn("t", noremap_opts)
M.cnoremap = make_keymap_fn("c", noremap_opts)

return M
