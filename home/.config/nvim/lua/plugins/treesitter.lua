local parsers = {
  "python", "rust", "solidity",
  "javascript", "typescript", "tsx", "html", "css",
  "json", "yaml", "toml",
  "dockerfile",
  "lua", "bash", "markdown", "markdown_inline",
  "gitcommit", "diff",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = "BufReadPost",
    config = function()
      -- Auto-install missing parsers on first BufReadPost
      local installed = require("nvim-treesitter.config").get_installed()
      local missing = vim.tbl_filter(function(p)
        return not vim.list_contains(installed, p)
      end, parsers)
      if #missing > 0 then
        require("nvim-treesitter.install").install(missing)
      end
    end,
  },
}
