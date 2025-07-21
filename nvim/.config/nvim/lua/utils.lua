local api = vim.api
local M = {}

local function make_keymap_fn(mode, o)
  local parent_opts = vim.deepcopy(o)
  return function(combo, mapping, opts)
    assert(combo ~= mode, string.format("The combo should not be the same as the mode for %s", combo))
    local _opts = opts and vim.deepcopy(opts) or {}

    if type(mapping) == "function" then
      error("Function mappings are not supported in this keymap utility. Use vim.keymap.set directly for function mappings.")
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

local map_opts = {noremap = false, silent = true}
M.map = make_keymap_fn("", map_opts)
M.nmap = make_keymap_fn("n", map_opts)
M.xmap = make_keymap_fn("x", map_opts)
M.imap = make_keymap_fn("i", map_opts)
M.vmap = make_keymap_fn("v", map_opts)
M.omap = make_keymap_fn("o", map_opts)
M.tmap = make_keymap_fn("t", map_opts)
M.smap = make_keymap_fn("s", map_opts)
M.cmap = make_keymap_fn("c", map_opts)

local noremap_opts = {noremap = true, silent = true}
M.nnoremap = make_keymap_fn("n", noremap_opts)
M.xnoremap = make_keymap_fn("x", noremap_opts)
M.vnoremap = make_keymap_fn("v", noremap_opts)
M.inoremap = make_keymap_fn("i", noremap_opts)
M.onoremap = make_keymap_fn("o", noremap_opts)
M.tnoremap = make_keymap_fn("t", noremap_opts)
M.cnoremap = make_keymap_fn("c", noremap_opts)

-- Performance utilities for large file detection
function M.is_large_file(bufnr, threshold)
  bufnr = bufnr or 0
  threshold = threshold or (100 * 1024) -- 100KB default
  
  local filename = api.nvim_buf_get_name(bufnr)
  if filename == "" then return false end
  
  local ok, stats = pcall((vim.uv or vim.loop).fs_stat, filename)
  if ok and stats and stats.size > threshold then
    return true
  end
  return false
end

function M.is_medium_file(bufnr, threshold)
  bufnr = bufnr or 0
  threshold = threshold or (10 * 1024) -- 10KB default
  
  local filename = api.nvim_buf_get_name(bufnr)
  if filename == "" then return false end
  
  local ok, stats = pcall((vim.uv or vim.loop).fs_stat, filename)
  if ok and stats and stats.size > threshold then
    return true
  end
  return false
end

-- Harpoon integration utilities
function M.get_harpoon_file_mapping()
  local ok, harpoon = pcall(require, "harpoon")
  if not ok then return {} end
  
  local list = harpoon:list()
  if not list or not list.items then return {} end
  
  local mapping = {}
  for i, item in ipairs(list.items) do
    if item.value then
      -- Create mapping for both absolute and relative paths
      local abs_path = vim.fn.fnamemodify(item.value, ":p")
      local rel_path = item.value
      mapping[abs_path] = i
      mapping[rel_path] = i
    end
  end
  
  return mapping
end

function M.get_harpoon_number_for_buffer(bufnr)
  bufnr = bufnr or 0
  local filename = api.nvim_buf_get_name(bufnr)
  if filename == "" then return nil end
  
  -- Get fresh mapping each time to ensure accuracy
  local ok, harpoon = pcall(require, "harpoon")
  if not ok then return nil end
  
  local list = harpoon:list()
  if not list or not list.items then return nil end
  
  -- Get various path formats for this buffer
  local abs_path = vim.fn.fnamemodify(filename, ":p")
  local rel_path = vim.fn.fnamemodify(filename, ":.")
  local tail_name = vim.fn.fnamemodify(filename, ":t")
  
  -- Check each harpoon item
  for i, item in ipairs(list.items) do
    if item.value then
      local item_abs = vim.fn.fnamemodify(item.value, ":p")
      local item_rel = item.value
      
      -- Match by absolute path (most reliable)
      if abs_path == item_abs then
        return i
      end
      
      -- Match by relative path
      if filename == item_rel or rel_path == item_rel then
        return i
      end
    end
  end
  
  return nil
end

return M
