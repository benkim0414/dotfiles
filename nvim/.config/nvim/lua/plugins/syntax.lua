return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    config = function()
      local ts_install = require('nvim-treesitter.install')

      -- Install essential parsers on startup (async, skips already-installed)
      ts_install.install({ 'lua', 'go', 'python', 'json', 'markdown' })

      -- Auto-install parsers when opening a new filetype
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("TSAutoInstall", { clear = true }),
        callback = function(ev)
          local lang = vim.treesitter.language.get_lang(ev.match) or ev.match
          if not pcall(vim.treesitter.get_parser, ev.buf, lang) then
            ts_install.install({ lang })
          end
        end,
      })

      -- Disable treesitter highlighting for large files
      vim.api.nvim_create_autocmd("BufReadPost", {
        group = vim.api.nvim_create_augroup("TSLargeFileDisable", { clear = true }),
        callback = function(ev)
          local utils = require("utils")
          if utils.is_large_file(ev.buf) then
            pcall(vim.treesitter.stop, ev.buf)
          end
        end,
      })

      -- Configure textobjects options
      require('nvim-treesitter-textobjects').setup({
        select = {
          lookahead = true,
          include_surrounding_whitespace = true,
        },
        move = {
          set_jumps = true,
        },
      })

      -- Text object select keymaps
      local select = require('nvim-treesitter-textobjects.select')
      local keymap = vim.keymap.set
      keymap({ "x", "o" }, "ib", function() select.select_textobject("@block.inner", "textobjects") end)
      keymap({ "x", "o" }, "ab", function() select.select_textobject("@block.outer", "textobjects") end)
      keymap({ "x", "o" }, "if", function() select.select_textobject("@function.inner", "textobjects") end)
      keymap({ "x", "o" }, "af", function() select.select_textobject("@function.outer", "textobjects") end)
      keymap({ "x", "o" }, "ic", function() select.select_textobject("@class.inner", "textobjects") end)
      keymap({ "x", "o" }, "ac", function() select.select_textobject("@class.outer", "textobjects") end)

      -- Text object move keymaps
      local move = require('nvim-treesitter-textobjects.move')
      keymap({ "n", "x", "o" }, "]f", function() move.goto_next_start("@function.outer", "textobjects") end)
      keymap({ "n", "x", "o" }, "]c", function() move.goto_next_start("@class.outer", "textobjects") end)
      keymap({ "n", "x", "o" }, "]F", function() move.goto_next_end("@function.outer", "textobjects") end)
      keymap({ "n", "x", "o" }, "]C", function() move.goto_next_end("@class.outer", "textobjects") end)
      keymap({ "n", "x", "o" }, "[f", function() move.goto_previous_start("@function.outer", "textobjects") end)
      keymap({ "n", "x", "o" }, "[c", function() move.goto_previous_start("@class.outer", "textobjects") end)
      keymap({ "n", "x", "o" }, "[F", function() move.goto_previous_end("@function.outer", "textobjects") end)
      keymap({ "n", "x", "o" }, "[C", function() move.goto_previous_end("@class.outer", "textobjects") end)
    end,
  },
}
