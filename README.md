# cmdwin.nvim
A neovim extanstion for applaying commands that you don't want shortcuts for. 

## Usage

```lua
require('cmdwin').setup()
```

```lua
require('cmdwin').setup({
    keymap = '<leader>p',  -- optional, this is the default
    command_map = {
        ["Find File"] = "Telescope find_files",
        ["Git Status"] = "Git",
        ["Format"] = "lua vim.lsp.buf.format()",
        -- ... more commands ...
    },
    navigation = {
        up = '<C-k>',
        down = '<C-j>',
    },
    style = {
        prompt = "> ",
        separator = "----------------------------------------",
        selected = ">",
        unselected = "  ",
    },
})
``` 
