vim.cmd([[
"Use 24-bit (true-color) mode in Vim/Neovim when outside tmux.
"If you're using tmux version 2.2 or later, you can remove the outermost $TMUX check and use tmux's 24-bit color support
"(see < http://sunaku.github.io/tmux-24bit-color.html#usage > for more information.)
if (empty($TMUX) && getenv('TERM_PROGRAM') != 'Apple_Terminal')
  if (has('nvim'))
    "For Neovim 0.1.3 and 0.1.4 < https://github.com/neovim/neovim/pull/2198 >
    let $NVIM_TUI_ENABLE_TRUE_COLOR=1
  endif
  "For Neovim > 0.1.5 and Vim > patch 7.4.1799 < https://github.com/vim/vim/commit/61be73bb0f965a895bfb064ea3e55476ac175162 >
  "Based on Vim patch 7.4.1770 (`guicolors` option) < https://github.com/vim/vim/commit/8a633e3427b47286869aa4b96f2bfc1fe65b25cd >
  " < https://github.com/neovim/neovim/wiki/Following-HEAD#20160511 >
  if (has('termguicolors'))
    set termguicolors
  endif
endif
]])

vim.o.number = true
vim.o.numberwidth = 5
vim.o.relativenumber = true
vim.o.ruler = true

vim.o.expandtab = true
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.smarttab = true
vim.o.autoindent = true

vim.o.autowrite = true

vim.o.hlsearch = true
vim.o.incsearch = true
vim.o.ignorecase = true
vim.o.smartcase = true

vim.g.mapleader = ','
vim.g.maplocalleader = ','
vim.keymap.set('', 'q:', '<Cmd>:q<CR>')
vim.api.nvim_set_keymap('n', '<leader>w', '<Cmd>w!<CR>', {noremap = true})
vim.api.nvim_set_keymap('n', '<leader>q', '<Cmd>q!<CR>', {noremap = true})
vim.api.nvim_set_keymap('n', '<leader>wa', '<Cmd>wa<CR>', {noremap = true})

vim.keymap.set('n', 'j', 'gj')
vim.keymap.set('n', 'k', 'gk')

vim.api.nvim_set_keymap('n', '0', '^', {noremap = true})
vim.api.nvim_set_keymap('n', '^', '0', {noremap = true})

vim.api.nvim_set_keymap('n', '<C-Space>', '<Esc>:noh<CR>', {noremap = true})
vim.api.nvim_set_keymap('v', '<C-Space>', '<Esc>gV', {noremap = true})
vim.api.nvim_set_keymap('o', '<C-Space>', '<Esc>', {noremap = true})
vim.api.nvim_set_keymap('c', '<C-Space>', '<C-c>', {noremap = true})
vim.api.nvim_set_keymap('i', '<C-Space>', '<Esc>', {noremap = true})
vim.api.nvim_set_keymap('n', '<C-@>', '<Esc>:noh<CR>', {noremap = true})
vim.api.nvim_set_keymap('v', '<C-@>', '<Esc>gV', {noremap = true})
vim.api.nvim_set_keymap('o', '<C-@>', '<Esc>', {noremap = true})
vim.api.nvim_set_keymap('c', '<C-@>', '<C-c>', {noremap = true})
vim.api.nvim_set_keymap('i', '<C-@>', '<Esc>', {noremap = true})

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  {
    'morhetz/gruvbox',
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd([[colorscheme gruvbox]])
    end,
  },

  'tpope/vim-commentary',
  'tpope/vim-fugitive',
  'tpope/vim-repeat',
  'tpope/vim-surround',
  'tpope/vim-unimpaired',

  {
    'kana/vim-textobj-line',
    dependencies = 'kana/vim-textobj-user',
  },
  {
    'kana/vim-textobj-indent',
    dependencies = 'kana/vim-textobj-user',
  },
  {
    'kana/vim-textobj-entire',
    dependencies = 'kana/vim-textobj-user',
  },

  'christoomey/vim-system-copy',
  'christoomey/vim-tmux-navigator',

  'pbrisbin/vim-mkdir',

  'vim-scripts/ReplaceWithRegister',

  'whiteinge/diffconflicts',

  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
  },
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    dependencies = 'nvim-treesitter/nvim-treesitter',
  },

  'neovim/nvim-lspconfig',
  'hrsh7th/nvim-cmp',
  'hrsh7th/cmp-nvim-lsp',
  'hrsh7th/cmp-vsnip',
  'hrsh7th/vim-vsnip',

  {
    'nvim-telescope/telescope.nvim',
    dependencies = 'nvim-lua/plenary.nvim',
  },
  {
    'nvim-telescope/telescope-fzf-native.nvim',
    build = 'make',
  },

  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    init = function()
      vim.o.timeout = true
      vim.o.timeoutlen = 300
    end,
  },
})

require('nvim-treesitter.configs').setup {
  ensure_installed = {'typescript', 'javascript', 'jsdoc', 'json', 'markdown'},
  sync_install = false,
  highlight = {
    enable = true,
    additional_vim_regex_highlighting = false,
  },
  textobjects = {
    select = {
      enable = true,
      lookahead = true,
      keymaps = {
        ['ib'] = '@block.inner',
        ['ab'] = '@block.outer',
        ['ic'] = '@class.inner',
        ['ac'] = '@class.outer',
        ['if'] = '@function.inner',
        ['af'] = '@function.outer',
      },
    },
    move = {
      enable = true,
      set_jumps = true,
      goto_next_start = {
        [']m'] = '@function.outer',
        [']]'] = '@class.outer',
      },
      goto_next_end = {
        [']M'] = '@function.outer',
        [']['] = '@class.outer',
      },
      goto_previous_start = {
        ['[m'] = '@function.outer',
        ['[['] = '@class.outer',
      },
      goto_previous_end = {
        ['[M'] = '@function.outer',
        ['[]'] = '@class.outer',
      },
    },
  },
}

local opts = {noremap = true, silent = true}
vim.api.nvim_set_keymap('n', '<Space>e', '<Cmd>lua vim.diagnostic.open_float()<CR>', opts)
vim.api.nvim_set_keymap('n', '[d', '<Cmd>lua vim.diagnostic.goto_prev()<CR>', opts)
vim.api.nvim_set_keymap('n', ']d', '<Cmd>lua vim.diagnostic.goto_next()<CR>', opts)
vim.api.nvim_set_keymap('n', '<Space>q', '<Cmd>lua vim.diagnostic.setloclist()<CR>', opts)

local on_attach = function(client, bufnr)
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gD', '<Cmd>lua vim.lsp.buf.declaration()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gd', '<Cmd>lua vim.lsp.buf.definition()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'K', '<Cmd>lua vim.lsp.buf.hover()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gi', '<Cmd>lua vim.lsp.buf.implementation()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Space>wa', '<Cmd>lua vim.lsp.buf.add_workspace_folder()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Space>wr', '<Cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Space>wl', '<Cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Space>D', '<Cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Space>rn', '<Cmd>lua vim.lsp.buf.rename()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Space>ca', '<Cmd>lua vim.lsp.buf.code_action()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gr', '<Cmd>lua vim.lsp.buf.references()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Space>f', function()
    vim.lsp.buf.format {async = true}
  end, opts)
end

local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

local servers = {'tsserver'}
for _, lsp in pairs(servers) do
  require('lspconfig')[lsp].setup {
    on_attach = on_attach,
    capabilities = capabilities,
    flags = {
      debounce_text_changes = 150,
    }
  }
end

local feedkey = function(key, mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), mode, true)
end

local cmp = require('cmp')
cmp.setup({
  snippet = {
    expand = function(args)
      vim.fn['vsnip#anonymous'](args.body)
    end,
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-b>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-e>'] = cmp.mapping.abort(),
    ['<CR>'] = cmp.mapping.confirm({select = true}),
    ['<Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      elseif vim.fn['vsnip#available'](1) == 1 then
        feedkey('<plug>(vsnip-expand-or-jump)', '')
      elseif has_words_before() then
        cmp.complete()
      else
        fallback()
      end
    end, {'i', 's'}),
    ['<S-Tab>'] = cmp.mapping(function()
      if cmp.visible() then
        cmp.select_prev_item()
      elseif vim.fn['vsnip#jumpable'](-1) == 1 then
        feedkey('<plug>(vsnip-jump-prev)', '')
      end
    end, {'i', 's'}),
  }),
  sources = cmp.config.sources({
    {name = 'nvim_lsp'},
    {name = 'vsnip'},
  }, {
    {name = 'buffer'},
  }),
})

local config = require('telescope.config')
local vimgrep_arguments = {unpack(config.values.vimgrep_arguments)}
table.insert(vimgrep_arguments, '--hidden')
table.insert(vimgrep_arguments, '--glob')
table.insert(vimgrep_arguments, '!**/.git/*')

require('telescope').setup {
  defaults = {
    file_ignore_patterns = {'node_modules'},
    vimgrep_arguments = vimgrep_arguments,
  },
  pickers = {
    find_files = {
      find_command = { 'rg', '--files', '--hidden', '--glob', '!**/.git/*' },
    },
  },
}

require('telescope').load_extension('fzf')

local builtin = require('telescope.builtin')
vim.keymap.set('n', '<C-p>', builtin.find_files)
vim.keymap.set('n', '<Leader>rg', builtin.live_grep)
vim.keymap.set('n', '<Leader>B', builtin.buffers)
vim.keymap.set('n', '<Leader>h', builtin.buffers)
