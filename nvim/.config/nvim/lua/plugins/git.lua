return {
  {
    "tpope/vim-fugitive",
    cmd = {
      "Git",
      "GBrowse",
      "Gdiffsplit",
      "Gvdiffsplit",
      "Gcommit",
      "Gblame",
      "Glog",
      "Gwrite",
      "Gread",
    },
    keys = {
      -- Core Git Operations (Most frequent = shortest keys)
      { "<Leader>gg", "<Cmd>Git<CR><Cmd>only<CR>", desc = "Git Status (Full)" },
      { "<Leader>gc", "<Cmd>Gcommit<CR>", desc = "Git Commit" },
      { "<Leader>gr", "<Cmd>Git<CR><Cmd>only<CR>cw", desc = "Git Reword Last Commit" },
      { "<Leader>gR", "<Cmd>Git<CR><Cmd>only<CR>ca", desc = "Git Reword Last Commit (Verbose)" },
      { "<Leader>gp", "<Cmd>Git push<CR>", desc = "Git Push" },
      
      -- File Operations (Intuitive)
      { "<Leader>ga", "<Cmd>Gwrite<CR>", desc = "Git Add File" },
      { "<Leader>gu", "<Cmd>Gread<CR>", desc = "Git Restore File" },
      
      -- View Operations
      { "<Leader>gd", "<Cmd>Gdiffsplit<CR>", desc = "Git Diff" },
      { "<Leader>gb", "<Cmd>Gblame<CR>", desc = "Git Blame" },
      { "<Leader>gl", "<Cmd>Git pull<CR>", desc = "Git Pull" },
      { "<Leader>gL", "<Cmd>Glog<CR>", desc = "Git Log" },
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
              vim.cmd.normal({ ']h', bang = true })
            else
              gitsigns.nav_hunk('next')
            end
          end, { desc = "Next hunk" })

          map('n', '[h', function()
            if vim.wo.diff then
              vim.cmd.normal({ '[h', bang = true })
            else
              gitsigns.nav_hunk('prev')
            end
          end, { desc = "Previous hunk" })

          -- Hunk Actions (Frequent = short)
          map('n', '<Leader>hs', gitsigns.stage_hunk, { desc = "Stage Hunk" })
          map('n', '<Leader>hr', gitsigns.reset_hunk, { desc = "Reset Hunk" })
          map('n', '<Leader>hp', gitsigns.preview_hunk, { desc = "Preview Hunk" })
          map('n', '<Leader>hu', gitsigns.undo_stage_hunk, { desc = "Undo Stage Hunk" })
          map('v', '<Leader>hs', function() gitsigns.stage_hunk { vim.fn.line('.'), vim.fn.line('v') } end, { desc = "Stage Hunk (Visual)" })
          map('v', '<Leader>hr', function() gitsigns.reset_hunk { vim.fn.line('.'), vim.fn.line('v') } end, { desc = "Reset Hunk (Visual)" })
          
          -- Buffer-wide Actions
          map('n', '<Leader>hS', gitsigns.stage_buffer, { desc = "Stage All Hunks" })
          map('n', '<Leader>hR', gitsigns.reset_buffer, { desc = "Reset All Hunks" })
          
          -- View Operations
          map('n', '<Leader>hb', function() gitsigns.blame_line { full = true } end, { desc = "Blame Line" })
          map('n', '<Leader>hd', gitsigns.diffthis, { desc = "Diff This" })
          map('n', '<Leader>hD', function() gitsigns.diffthis('~') end, { desc = "Diff This (Cached)" })
          
          -- Toggles (Less frequent)
          map('n', '<Leader>tb', gitsigns.toggle_current_line_blame, { desc = "Toggle Line Blame" })
          map('n', '<Leader>td', gitsigns.toggle_deleted, { desc = "Toggle Deleted Lines" })

          map({ 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>')
        end
      }
    end
  },
}
