# tex-autopairs.nvim

Generic Neovim autopair plugins are excellent: they cover almost every language, add no ceremony, and stay out of the way. TeX is the one place where their model breaks down. A delimiter may span several characters, display math can use a two-character closer identical to its opener (`$$`), and every closer command begins with the same backslash as every ordinary command.

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
  ```text
  `' and ``''
  ```
- A different closing bracket can replace the generated one, e.g. `[0, 1)` or `\left[0, 1\right)`
  for a left-closed, right-open interval.
- `\begin{` also inserts `\end{}` and synchronizes the environment name until
  you type `}` or leave the name, Insert mode, or buffer.

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

Lists of pairs and modifiers can be configured via `setup`.
Pass `definitions` or `modifiers` to replace either list.
Default lists are in [config.lua](lua/tex-autopairs/config.lua).

```lua
require("tex-autopairs").setup({
	definitions = {
		{ open = "(", close = ")", standalone = true, sized = true, replaceable = true },
		{ open = "[", close = "]", standalone = true, sized = true, replaceable = true },
		{ open = "{", close = "}", standalone = true, replaceable = true },
	},
	modifiers = {
		{ open = "\\left", close = "\\right" },
		{ open = "\\big", close = "\\big" },
	},
})
```

- `open`/`close`: opening token and its matching closing token.
- `standalone`: pair direct input, e.g. `(` inserts `)`.
- `sized`: combine the definition with each modifier.
- `replaceable`: allow closer overrides, e.g. typing `)` replaces the generated `]` in `[0, 1)`.

Omitted flags are false.

Dollar pairing is always enabled since it contains some different logic;
environment pairing requires a standalone `{`/`}` definition.

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
