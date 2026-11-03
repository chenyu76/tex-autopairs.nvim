# tex-autopairs.nvim

Generic Neovim autopair plugins are excellent: they cover almost every language, add
no ceremony, and stay out of the way. TeX is the one place where their model
breaks down. A delimiter may span several characters: the opener is often a
command (e.g. `\left(`, `\langle`), the closer is a different command (`\right)`,
`\rangle`), display math can use a two-character closer identical to its opener
(`$$`), and every closer command begins with the same backslash as every
ordinary command.

This plugin provides Insert-mode pairing for filetype `tex` to handle those cases.

Requires Neovim 0.10 or newer.

## Supported pairs

This plugin supports the following autopairs:

- `$` gives `$`/`$`; a second `$` in that empty pair widens it to `$$`/`$$`.
  Further dollars close the display pair.
- `\(`, `\[`, `\{`, `(`, `[`, `{` give their matching pair.
- Named delimiters: `\langle`/`\rangle`, `\lceil`/`\rceil`,
  `\lfloor`/`\rfloor`, `\lbrace`/`\rbrace`, `\lbrack`/`\rbrack`,
  `\lparen`/`\rparen`, `\lvert`/`\rvert`, `\lVert`/`\rVert`,
  `\lgroup`/`\rgroup`, `\lmoustache`/`\rmoustache`, and `\|`/`\|`.
- Size commands `\left`/`\right`, `\bigl`/`\bigr`, `\Bigl`/`\Bigr`,
  `\biggl`/`\biggr`, `\Biggl`/`\Biggr`, and `\big`, `\Big`, `\bigg`, `\Bigg`
  combine with parentheses, brackets, escaped braces, the named delimiters
  above, `<`/`>`, `|`, `\vert`, and `\Vert`.
- A backtick opens a quote pair closed by an apostrophe, i.e.
    ```
    `' and ``''
	```

See `:help tex-autopairs-pairs` and `:help tex-autopairs-environments` for the
complete input, replacement, and synchronization rules.

## Installation
Install using your favorite package manager.

### [vim.pack](https://neovim.io/doc/user/pack/#vim.pack)

```lua
vim.pack.add({
	{ src = "https://github.com/chenyu76/tex-autopairs.nvim" },
})

require("tex-autopairs").setup()
```

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "chenyu76/tex-autopairs.nvim",
    config = function()
        require("tex-autopairs").setup()
    end
}

```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use({
	"chenyu76/tex-autopairs.nvim",
	config = function()
		require("tex-autopairs").setup()
	end,
})
```

## Configuration

The plugin currently has no configuration options.

## Using it together with [nvim-autopairs](https://github.com/windwp/nvim-autopairs)

```lua
-- setup nvim-autopairs with your custom settings
local autopairs = require("nvim-autopairs")
autopairs.setup({
	disable_filetype = { "TelescopePrompt", "spectre_panel", "snacks_picker_input" },
})

-- then disable all tex autopairs for nvim-autopairs
for _, rule in ipairs(autopairs.config.rules) do
	rule.not_filetypes = rule.not_filetypes or {}
	table.insert(rule.not_filetypes, "tex")
end
autopairs.force_attach()

-- setup tex-autopairs.nvim
require("tex-autopairs").setup()
```

NOTE: Currently (Nov 3, 2026), you cannot call `require("nvim-autopairs").setup({disable_filetype = {"tex"}})` and then setup this plugin. Check [issue #554](https://github.com/windwp/nvim-autopairs/issues/554) for more information.
