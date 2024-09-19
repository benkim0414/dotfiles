return {
  {
    "kdheepak/lazygit.nvim",
    cmd = {
      "LazyGit",
      "LazyGitConfig",
      "LazyGitCurrentFile",
      "LazyGitFilter",
      "LazyGitFilterCurrentFile",
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    keys = {
      { "<Leader>lg", "<Cmd>LazyGit<CR>", desc = "LazyGit" },
    },
  },
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup {
        on_attach = function(bufnr)
          local gitsigns = require('gitsigns')

          local function map(mode, l, r, opts)
            opts = opts or {}
            opts.buffer = bufnr
            vim.keymap.set(mode, l, r, opts)
          end

          map('n', ']h', function()
            if vim.wo.diff then
              vim.cmd.normal({']h', bang = true})
            else
              gitsigns.nav_hunk('next')
            end
          end)

          map('n', '[h', function()
            if vim.wo.diff then
              vim.cmd.normal({'[h', bang = true})
            else
              gitsigns.nav_hunk('prev')
            end
          end)

          map('n', '<Leader>hs', gitsigns.stage_hunk)
          map('n', '<Leader>hr', gitsigns.reset_hunk)
          map('v', '<Leader>hs', function() gitsigns.stage_hunk {vim.fn.line('.'), vim.fn.line('v')} end)
          map('v', '<Leader>hr', function() gitsigns.reset_hunk {vim.fn.line('.'), vim.fn.line('v')} end)
          map('n', '<Leader>hS', gitsigns.stage_buffer)
          map('n', '<Leader>hu', gitsigns.undo_stage_hunk)
          map('n', '<Leader>hR', gitsigns.reset_buffer)
          map('n', '<Leader>hp', gitsigns.preview_hunk)
          map('n', '<Leader>hb', function() gitsigns.blame_line{full=true} end)
          map('n', '<Leader>tb', gitsigns.toggle_current_line_blame)
          map('n', '<Leader>hd', gitsigns.diffthis)
          map('n', '<Leader>hD', function() gitsigns.diffthis('~') end)
          map('n', '<Leader>td', gitsigns.toggle_deleted)

          map({'o', 'x'}, 'ih', ':<C-U>Gitsigns select_hunk<CR>')
        end
      }
    end
  },
  {
    "pwntester/octo.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("octo").setup()
    end
  },
}
