-- By convention, nvim Lua plugins include a setup function that takes a table
-- so that users of the plugin can configure it using this pattern:
--
-- require'myluamodule'.setup({p1 = "value1"})
local M = {}

-- Forward declarations of functions
local close_floating_window
local filter_commands
local update_window_content
local handle_navigation
local execute_selected_command
local handle_keypress
local open_floating_window

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
    up = 11,    -- Ctrl-k (11 is the ASCII code for Ctrl-k)
    down = 10,  -- Ctrl-j (10 is the ASCII code for Ctrl-j)
}

-- Function implementations
close_floating_window = function()
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

filter_commands = function(search_term)
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

update_window_content = function()
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

    -- Prepare lines array
    local lines = {}
    
    -- Add search prompt
    table.insert(lines, '> ' .. (current_search or ""))
    
    -- Add separator
    table.insert(lines, string.rep('-', 30))
    
    -- Add filtered commands with selection highlight
    for i, cmd_name in ipairs(current_commands) do
        if i == selected_index then
            table.insert(lines, '> ' .. (cmd_name or ""))
        else
            table.insert(lines, '  ' .. (cmd_name or ""))
        end
    end
    
    -- Update buffer content safely
    pcall(vim.api.nvim_buf_set_lines, current_buf_id, 0, -1, false, lines)
    
    -- Move cursor to end of search line safely
    pcall(vim.api.nvim_win_set_cursor, current_win_id, {1, #current_search + 2})
end

handle_navigation = function(direction)
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

execute_selected_command = function()
    if selected_index > 0 and selected_index <= #current_commands then
        local selected_name = current_commands[selected_index]
        local command = command_map[selected_name]
        if command then
            -- Close the window first
            close_floating_window()
            -- Schedule the command execution for next event loop
            vim.schedule(function()
                vim.cmd(command)
            end)
        end
    end
end

handle_keypress = function()
    -- Use getcharstr() instead of getchar() for better key handling
    local ok, char = pcall(vim.fn.getcharstr)
    if not ok then
        return
    end

    -- Handle special keys
    if char == vim.api.nvim_replace_termcodes("<ESC>", true, false, true) then
        close_floating_window()
        return
    elseif char == vim.api.nvim_replace_termcodes("<CR>", true, false, true) then
        execute_selected_command()
        return
    elseif char == vim.api.nvim_replace_termcodes("<BS>", true, false, true) then
        if #current_search > 0 then
            current_search = current_search:sub(1, -2)
            -- Reset selection when search changes
            selected_index = 1
            update_window_content()
        end
        return
    -- Handle navigation with control keys
    elseif char == string.char(nav_keymaps.up) then
        handle_navigation('up')
        return
    elseif char == string.char(nav_keymaps.down) then
        handle_navigation('down')
        return
    end
    
    -- Add printable characters to search
    if char:match("^[%g%s]$") and not char:match("[\n\r]") then
        current_search = current_search .. char
        -- Reset selection when search changes
        selected_index = 1
        update_window_content()
    end
end

open_floating_window = function()
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
        -- Convert string keymaps to their ASCII values if they're Ctrl combinations
        if opts.navigation.up then
            if opts.navigation.up:match('^<C%-%a>$') then
                local key = string.lower(opts.navigation.up:match('^<C%-(%a)>$'))
                nav_keymaps.up = string.byte(key) - string.byte('a') + 1
            else
                nav_keymaps.up = opts.navigation.up
            end
        end
        if opts.navigation.down then
            if opts.navigation.down:match('^<C%-%a>$') then
                local key = string.lower(opts.navigation.down:match('^<C%-(%a)>$'))
                nav_keymaps.down = string.byte(key) - string.byte('a') + 1
            else
                nav_keymaps.down = opts.navigation.down
            end
        end
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
