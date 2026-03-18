return {
  -- Mason: auto-install LSP servers
  {
    "mason-org/mason.nvim",
    opts = {},
  },
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = { "mason-org/mason.nvim" },
    opts = {
      ensure_installed = {
        "pyright",
        "ruff",
        "rust_analyzer",
        "ts_ls",
        "html",
        "cssls",
        "jsonls",
        "yamlls",
        "dockerls",
        "docker_compose_language_service",
        "lua_ls",
        "solidity_ls_nomicfoundation",
      },
    },
  },
  -- LSP keymaps and diagnostics (native vim.lsp.config in 0.11+)
  {
    "mason-org/mason-lspconfig.nvim",
    config = function()
      -- Keymaps on LSP attach
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local map = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = args.buf, desc = desc })
          end
          map("gd", vim.lsp.buf.definition, "Go to definition")
          map("gr", vim.lsp.buf.references, "References")
          map("gi", vim.lsp.buf.implementation, "Implementation")
          map("K", vim.lsp.buf.hover, "Hover docs")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>rn", vim.lsp.buf.rename, "Rename")
          map("<leader>D", vim.lsp.buf.type_definition, "Type definition")
          map("[d", vim.diagnostic.goto_prev, "Prev diagnostic")
          map("]d", vim.diagnostic.goto_next, "Next diagnostic")
          map("<leader>e", vim.diagnostic.open_float, "Diagnostic float")
        end,
      })

      -- Diagnostic display
      vim.diagnostic.config({
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = " ",
            [vim.diagnostic.severity.WARN] = " ",
            [vim.diagnostic.severity.INFO] = " ",
            [vim.diagnostic.severity.HINT] = "󰌵 ",
          },
        },
        virtual_text = { spacing = 4, prefix = "●" },
        float = { border = "rounded" },
      })

      -- Server-specific settings via native vim.lsp.config
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
          },
        },
      })

      vim.lsp.config("rust_analyzer", {
        settings = {
          ["rust-analyzer"] = {
            check = { command = "clippy" },
          },
        },
      })

      -- Enable all servers installed by mason-lspconfig
      vim.lsp.enable({
        "pyright", "ruff", "rust_analyzer", "ts_ls",
        "html", "cssls", "jsonls", "yamlls",
        "dockerls", "docker_compose_language_service",
        "lua_ls", "solidity_ls_nomicfoundation",
      })
    end,
  },
}
