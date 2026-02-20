-- OpenCode.nvim configuration
-- https://github.com/NickvanDyke/opencode.nvim

require("opencode").setup {
  -- Provider configuration
  provider = "copilot", -- or "openai", "anthropic", "gemini", etc.

  -- Keybindings
  keymaps = {
    toggle = "<leader>oc", -- Toggle OpenCode window
    accept = "<Tab>",      -- Accept suggestion
    dismiss = "<C-]>",     -- Dismiss suggestion
  },

  -- Window configuration
  window = {
    width = 0.4,  -- 40% of screen width
    height = 0.6, -- 60% of screen height
    border = "rounded",
  },

  -- Enable/disable features
  features = {
    chat = true,       -- Enable chat interface
    completion = true, -- Enable code completion
    context = true,    -- Include file context
  },
}
