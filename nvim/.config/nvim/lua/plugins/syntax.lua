return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    config = function()
      local ts_install = require('nvim-treesitter.install')
      local missing_compiler_warned = false

      local function find_versioned_gcc()
        local matches = {}
        local seen = {}

        for _, dir in ipairs(vim.split(vim.env.PATH or "", ":", { trimempty = true })) do
          local ok, iter = pcall(vim.fs.dir, dir)
          if ok then
            for name, entry_type in iter do
              local path = vim.fs.joinpath(dir, name)
              if entry_type ~= "directory" and name:match("^gcc%-%d[%d%.]*$") and not seen[name] and vim.fn.executable(path) == 1 then
                seen[name] = true
                table.insert(matches, name)
              end
            end
          end
        end

        table.sort(matches, function(a, b)
          local a_version = tonumber(a:match("^gcc%-(%d+)")) or 0
          local b_version = tonumber(b:match("^gcc%-(%d+)")) or 0
          if a_version == b_version then
            return a > b
          end
          return a_version > b_version
        end)

        return matches[1]
      end

      local function get_treesitter_compiler()
        if vim.env.CC and vim.fn.executable(vim.env.CC) == 1 then
          return vim.env.CC
        end

        for _, compiler in ipairs({ "cc", "gcc", "clang" }) do
          if vim.fn.executable(compiler) == 1 then
            return compiler
          end
        end

        return find_versioned_gcc()
      end

      local function notify_missing_treesitter_compiler()
        if missing_compiler_warned then
          return
        end

        missing_compiler_warned = true
        vim.schedule(function()
          vim.notify(
            "Treesitter parser installation requires a C compiler (cc, gcc, clang, or Homebrew gcc-*). Install compiler tools, then run :TSUpdate.",
            vim.log.levels.WARN
          )
        end)
      end

      local function install_treesitter_parsers(langs)
        local compiler = get_treesitter_compiler()
        if compiler then
          if vim.env.CC ~= compiler then
            vim.env.CC = compiler
          end
          ts_install.install(langs)
        else
          notify_missing_treesitter_compiler()
        end
      end

      -- Install essential parsers on startup (async, skips already-installed)
      install_treesitter_parsers({ 'lua', 'go', 'python', 'json', 'markdown' })

      -- Auto-install parsers when opening a new filetype
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("TSAutoInstall", { clear = true }),
        callback = function(ev)
          local lang = vim.treesitter.language.get_lang(ev.match) or ev.match
          if not pcall(vim.treesitter.get_parser, ev.buf, lang) then
            install_treesitter_parsers({ lang })
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
