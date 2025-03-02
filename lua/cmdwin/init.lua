-- By convention, nvim Lua plugins include a setup function that takes a table
-- so that users of the plugin can configure it using this pattern:
--
-- require'myluamodule'.setup({p1 = "value1"})
local M = {}

-- Store the current window ID and buffer ID
local current_win_id = nil
local current_buf_id = nil

-- Store the command map
local command_map = {}

-- Store current search state
local current_search = ""
local selected_index = 0  -- 0 means no selection
local current_commands = {}  -- Store filtered commands for navigation

-- Store navigation keymaps
local nav_keymaps = {
    up = '<C-k>',      -- Default to vim-style navigation
    down = '<C-j>',
}

-- Function to filter commands based on search
local function filter_commands(search_term)
    local filtered = {}
    search_term = search_term:lower()
    for cmd_name, _ in pairs(command_map) do
        if cmd_name:lower():find(search_term, 1, true) then
            table.insert(filtered, cmd_name)
        end
    end
    table.sort(filtered)
    return filtered
end

-- Function to update window content
local function update_window_content()
    if not (current_win_id and vim.api.nvim_win_is_valid(current_win_id)) then
        return
    end

    -- Update filtered commands
    current_commands = filter_commands(current_search)
    
    -- Adjust selected_index if it's out of bounds
    if #current_commands == 0 then
        selected_index = 0
    elseif selected_index > #current_commands then
        selected_index = #current_commands
    end

    local lines = {
        '> ' .. current_search,  -- Search prompt
        string.rep('-', 30),     -- Simple separator
    }
    
    -- Add filtered commands with selection highlight
    for i, cmd_name in ipairs(current_commands) do
        if i == selected_index then
            table.insert(lines, '> ' .. cmd_name)  -- Simple arrow for selected item
        else
            table.insert(lines, '  ' .. cmd_name)  -- Add padding for unselected items
        end
    end
    
    -- Update buffer content
    vim.api.nvim_buf_set_lines(current_buf_id, 0, -1, false, lines)
    
    -- Move cursor to end of search line
    vim.api.nvim_win_set_cursor(current_win_id, {1, #current_search + 2})
end

-- Function to handle navigation
local function handle_navigation(direction)
    if #current_commands == 0 then
        return
    end

    if direction == 'up' then
        if selected_index <= 1 then
            selected_index = #current_commands
        else
            selected_index = selected_index - 1
        end
    elseif direction == 'down' then
        if selected_index >= #current_commands then
            selected_index = 1
        else
            selected_index = selected_index + 1
        end
    end
    
    update_window_content()
end

-- Function to handle key input
local function handle_keypress()
    local char = vim.fn.getchar()
    
    -- Handle special keys when they come as numbers
    if type(char) == "number" then
        -- Check for special keys
        if char == 27 then  -- Esc key
            close_floating_window()
            return
        elseif char == 13 then  -- Enter key
            -- TODO: Execute selected command
            return
        elseif char == 127 or char == 8 then  -- Backspace (different systems use different codes)
            if #current_search > 0 then
                current_search = current_search:sub(1, -2)
                -- Reset selection when search changes
                selected_index = 1
            end
            update_window_content()
            return
        end
        -- Convert regular characters to string
        char = vim.fn.nr2char(char)
    end
    
    -- Handle navigation keys
    if char == nav_keymaps.up then
        handle_navigation('up')
        return
    elseif char == nav_keymaps.down then
        handle_navigation('down')
        return
    end
    
    -- Add printable characters to search
    if char:match("^[%g%s]$") then  -- Only add printable characters and spaces
        current_search = current_search .. char
        -- Reset selection when search changes
        selected_index = 1
        update_window_content()
    end
end

-- Function to close the floating window
local function close_floating_window()
    -- First check if window exists and is valid
    if current_win_id and vim.api.nvim_win_is_valid(current_win_id) then
        -- Store IDs locally before resetting globals
        local win_to_close = current_win_id
        local buf_to_delete = current_buf_id
        
        -- Reset global IDs and search
        current_win_id = nil
        current_buf_id = nil
        current_search = ""
        selected_index = 0
        
        -- Close the window using local ID
        vim.api.nvim_win_close(win_to_close, true)
        
        -- Schedule buffer deletion for next event loop iteration
        vim.schedule(function()
            if buf_to_delete and vim.api.nvim_buf_is_valid(buf_to_delete) then
                vim.api.nvim_buf_delete(buf_to_delete, { force = true })
            end
        end)
    end
end

-- Function to open a floating window
local function open_floating_window()
    -- If window is already open, close it
    if current_win_id and vim.api.nvim_win_is_valid(current_win_id) then
        close_floating_window()
        return
    end

    -- Reset search and selection
    current_search = ""
    selected_index = 1  -- Start with first item selected

    -- Window configuration
    local width = 60
    local height = 10
    local bufnr = vim.api.nvim_create_buf(false, true)
    current_buf_id = bufnr
    
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
    current_win_id = vim.api.nvim_open_win(bufnr, true, win_opts)
    
    -- Set some buffer options
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
    vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
    
    -- Initialize window content
    update_window_content()
    
    -- Create a buffer-local autocommand group
    local group = vim.api.nvim_create_augroup('FloatingWindowClose_' .. bufnr, { clear = true })
    
    -- Add cleanup autocmd when window is closed
    vim.api.nvim_create_autocmd('BufWinLeave', {
        group = group,
        buffer = bufnr,
        callback = close_floating_window,
        once = true,
    })
    
    -- Start input loop
    vim.schedule(function()
        while current_win_id and vim.api.nvim_win_is_valid(current_win_id) do
            handle_keypress()
            vim.cmd('redraw')
        end
    end)
end

-- Setup function for configuration
function M.setup(opts)
    opts = opts or {}
    
    -- Store the command map
    command_map = opts.command_map or {}
    
    -- Store navigation keymaps if provided
    if opts.navigation then
        nav_keymaps.up = opts.navigation.up or nav_keymaps.up
        nav_keymaps.down = opts.navigation.down or nav_keymaps.down
    end
    
    -- Validate command map format
    for cmd_name, cmd_value in pairs(command_map) do
        if type(cmd_name) ~= "string" or type(cmd_value) ~= "string" then
            error("Command map must be in format { 'command_name': 'command_value' }")
        end
    end
    
    -- Set up the keymap (default to <leader>p if not specified)
    local keymap = opts.keymap or '<leader>p'
    vim.keymap.set('n', keymap, open_floating_window, {
        desc = 'Toggle floating window',
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
