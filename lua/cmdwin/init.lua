-- By convention, nvim Lua plugins include a setup function that takes a table
-- so that users of the plugin can configure it using this pattern:
--
-- require'myluamodule'.setup({p1 = "value1"})
local M = {}

-- Function to open a floating window
local function open_floating_window()
    -- Window configuration
    local width = 60
    local height = 10
    local bufnr = vim.api.nvim_create_buf(false, true)
    
    -- Calculate window position (centered)
    local ui = vim.api.nvim_list_uis()[1]
    local win_opts = {
        relative = 'editor',
        width = width,
        height = height,
        col = (ui.width - width) / 2,
        row = (ui.height - height) / 2,
        anchor = 'NW',
        style = 'minimal',
        border = 'rounded'
    }
    
    -- Create the window
    local win_id = vim.api.nvim_open_win(bufnr, true, win_opts)
    
    -- Set some buffer options
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
    vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
    
    -- You can add initial content to the buffer if needed
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {'Welcome to the floating window!'})
end

-- Setup function for configuration
function M.setup(opts)
    opts = opts or {}
    
    -- Set up the keymap (default to <leader>w if not specified)
    local keymap = opts.keymap or '<leader>w'
    vim.keymap.set('n', keymap, open_floating_window, {
        desc = 'Open floating window',
        silent = true
    })
end

-- Since this function doesn't have a `local` qualifier, it will end up in the
-- global namespace, and can be invoked from anywhere using:
--
-- :lua global_lua_function()
--
-- Personally, I feel that kind of global namespace pollution should probably
-- be avoided in order to prevent other modules from accidentally clashing with
-- my function names. While `global_lua_function` seems kind of rare, if I had
-- a function called `connect` in my module, I would be more concerned. So I
-- normally try to follow the pattern demonstrated by `local_lua_function`. The
-- right choice might depend on your circumstances.
function global_lua_function()
    print "nvim-example-lua-plugin.myluamodule.init global_lua_function: hello"
end

local function unexported_local_function()
    print "nvim-example-lua-plugin.myluamodule.init unexported_local_function: hello"
end

-- This function is qualified with `local`, so it's visibility is restricted to
-- this file. It is exported below in the return value from this module using a
-- Lua pattern that allows symbols to be selectively exported from a module by
-- adding them to a table that is returned from the file.
local function local_lua_function()
    print "nvim-example-lua-plugin.myluamodule.init local_lua_function: hello"
end

-- Create a command, ':DoTheThing'
vim.api.nvim_create_user_command(
    'DoTheThing',
    function(input)
        print "Something should happen here..."
    end,
    {bang = true, desc = 'a new command to do the thing'}
)

-- This is a duplicate of the keymap created in the VimL file, demonstrating how to create a
-- keymapping in Lua.
vim.keymap.set('n', 'M-C-G', local_lua_function, {desc = 'Run local_lua_function.', remap = false})

-- Create a named autocmd group for autocmds so that if this file/plugin gets reloaded, the existing
-- autocmd group will be cleared, and autocmds will be recreated, rather than being duplicated.
local augroup = vim.api.nvim_create_augroup('highlight_cmds', {clear = true})

vim.api.nvim_create_autocmd('ColorScheme', {
  pattern = 'rubber',
  group = augroup,
  -- There can be a 'command', or a 'callback'. A 'callback' will be a reference to a Lua function.
  command = 'highlight String guifg=#FFEB95',
  --callback = function()
  --  vim.api.nvim_set_hl(0, 'String', {fg = '#FFEB95'})
  --end
})

-- Returning a Lua table at the end allows fine control of the symbols that
-- will be available outside this file. Returning the table also allows the
-- importer to decide what name to use for this module in their own code.
--
-- Examples of how this module can be imported:
--    local mine = require('myluamodule')
--    mine.local_lua_function()
--    local myluamodule = require('myluamodule')
--    myluamodule.local_lua_function()
--    require'myluamodule'.setup({p1 = "value1"})
return M
