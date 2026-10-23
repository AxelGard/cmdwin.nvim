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

-- Style settings
local style = {
    prompt = '> ',
    separator = '----------------------------------------',
    selected = '> ',
    unselected = '  ',
}

-- Window settings
local window = {
    position = 'center',    -- 'center', 'top', 'bottom', 'left', 'right'
    width = 60,            -- window width
    height = 10,           -- window height
    padding = {            -- padding from screen edges when using position other than 'center'
        top = 2,
        right = 2,
        bottom = 2,
        left = 2
    },
    border = 'rounded'     -- border style
}

-- Convert a key notation such as '<C-k>' or '<Up>' to the string getcharstr() returns
local function keycode(key)
    return vim.api.nvim_replace_termcodes(key, true, false, true)
end

-- Store navigation keymaps (arrow keys always work as well)
local nav_keymaps = {
    up = keycode('<C-k>'),
    down = keycode('<C-j>'),
}

-- First visible command when the list is longer than the window
local scroll_offset = 0

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
        scroll_offset = 0

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
    -- vim.fn.tolower() also lowercases non-ASCII characters (e.g. Ö -> ö)
    search_term = vim.fn.tolower(search_term)
    for cmd_name, _ in pairs(command_map) do
        if vim.fn.tolower(cmd_name):find(search_term, 1, true) then
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
    table.insert(lines, style.prompt .. (current_search or ""))

    -- Add separator
    table.insert(lines, style.separator)

    -- Scroll so the selected command stays visible (prompt and separator take two lines)
    local visible = math.max(vim.api.nvim_win_get_height(current_win_id) - 2, 1)
    if selected_index > scroll_offset + visible then
        scroll_offset = selected_index - visible
    elseif selected_index > 0 and selected_index <= scroll_offset then
        scroll_offset = selected_index - 1
    end
    scroll_offset = math.max(math.min(scroll_offset, #current_commands - visible), 0)

    -- Add visible commands with selection highlight
    for i = scroll_offset + 1, math.min(scroll_offset + visible, #current_commands) do
        local cmd_name = current_commands[i]
        if i == selected_index then
            table.insert(lines, style.selected .. (cmd_name or ""))
        else
            table.insert(lines, style.unselected .. (cmd_name or ""))
        end
    end

    -- Update buffer content safely
    pcall(vim.api.nvim_buf_set_lines, current_buf_id, 0, -1, false, lines)

    -- Move cursor to end of search line safely
    pcall(vim.api.nvim_win_set_cursor, current_win_id, {1, #current_search + #style.prompt})
end

-- Redraw the screen and move the visible cursor to the window cursor.
-- A plain :redraw inside the input loop leaves the terminal cursor where it was.
local function redraw()
    if vim.api.nvim__redraw and current_win_id and vim.api.nvim_win_is_valid(current_win_id) then
        vim.api.nvim__redraw({ win = current_win_id, cursor = true, flush = true })
    else
        vim.cmd('redraw')
    end
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
                local ok, err = pcall(vim.cmd, command)
                if not ok then
                    vim.notify('cmdwin: ' .. selected_name .. ' failed: ' .. tostring(err), vim.log.levels.ERROR)
                end
            end)
        end
    end
end

handle_keypress = function()
    -- Use getcharstr() instead of getchar() for better key handling
    local ok, char = pcall(vim.fn.getcharstr)
    if not ok then
        -- getcharstr() throws on <C-c>
        close_floating_window()
        return
    end

    -- Handle special keys
    if char == keycode("<ESC>") or char == keycode("<C-c>") then
        close_floating_window()
        return
    elseif char == keycode("<CR>") then
        execute_selected_command()
        return
    elseif char == keycode("<BS>") or char == keycode("<C-h>") then
        if #current_search > 0 then
            -- Remove the last character, not the last byte (keeps UTF-8 intact)
            current_search = vim.fn.strcharpart(current_search, 0, vim.fn.strchars(current_search) - 1)
            -- Reset selection when search changes
            selected_index = 1
            update_window_content()
        end
        return
    -- Handle navigation with control keys
    elseif char == nav_keymaps.up or char == keycode("<Up>") then
        handle_navigation('up')
        return
    elseif char == nav_keymaps.down or char == keycode("<Down>") then
        handle_navigation('down')
        return
    end

    -- Add printable characters (including non-ASCII) to search, ignoring
    -- control characters and special keys such as <F1> (which start with 0x80)
    local first = char:byte(1)
    if first and first >= 32 and first ~= 127 and first ~= 128 then
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
    scroll_offset = 0

    -- Create buffer
    local bufnr = vim.api.nvim_create_buf(false, true)
    current_buf_id = bufnr

    -- Get editor dimensions (excluding the command line)
    local editor_width = vim.o.columns
    local editor_height = vim.o.lines - vim.o.cmdheight

    -- Keep the window (plus its border) inside the editor
    local border_size = (window.border == 'none' or window.border == '') and 0 or 2
    local width = math.max(math.min(window.width, editor_width - border_size), 1)
    local height = math.max(math.min(window.height, editor_height - border_size), 1)
    local total_width = width + border_size
    local total_height = height + border_size

    -- Calculate window position based on settings
    local col, row
    if window.position == 'top' then
        col = (editor_width - total_width) / 2
        row = window.padding.top
    elseif window.position == 'bottom' then
        col = (editor_width - total_width) / 2
        row = editor_height - total_height - window.padding.bottom
    elseif window.position == 'left' then
        col = window.padding.left
        row = (editor_height - total_height) / 2
    elseif window.position == 'right' then
        col = editor_width - total_width - window.padding.right
        row = (editor_height - total_height) / 2
    else -- 'center' (also the fallback for unknown positions)
        col = (editor_width - total_width) / 2
        row = (editor_height - total_height) / 2
    end
    col = math.max(math.min(math.floor(col), editor_width - total_width), 0)
    row = math.max(math.min(math.floor(row), editor_height - total_height), 0)

    -- Window configuration
    local win_opts = {
        relative = 'editor',
        width = width,
        height = height,
        col = col,
        row = row,
        anchor = 'NW',
        style = 'minimal',
        border = window.border
    }

    -- Create the window
    current_win_id = vim.api.nvim_open_win(bufnr, true, win_opts)

    -- Set buffer options
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].buftype = 'nofile'

    -- Set window options to use default colors (no highlighting)
    vim.wo[current_win_id].winhighlight = ''
    -- Let the cursor sit after the last typed character (normal mode would clamp it)
    vim.wo[current_win_id].virtualedit = 'onemore'

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
        redraw()
        while current_win_id and vim.api.nvim_win_is_valid(current_win_id) do
            handle_keypress()
            redraw()
        end
    end)
end

-- Setup function for configuration
function M.setup(opts)
    opts = opts or {}

    -- Store the command map
    command_map = opts.command_map or {}

    -- Update style settings if provided
    if opts.style then
        for k, v in pairs(opts.style) do
            if style[k] then
                style[k] = v
            end
        end
    end

    -- Update window settings if provided
    if opts.window then
        -- Update simple properties
        if opts.window.position then
            window.position = opts.window.position
        end
        if opts.window.width then
            window.width = opts.window.width
        end
        if opts.window.height then
            window.height = opts.window.height
        end
        if opts.window.border then
            window.border = opts.window.border
        end

        -- Update padding if provided
        if opts.window.padding then
            for k, v in pairs(opts.window.padding) do
                if window.padding[k] then
                    window.padding[k] = v
                end
            end
        end
    end

    -- Store navigation keymaps if provided
    if opts.navigation then
        -- Convert key notation (e.g. '<C-k>', '<Up>', '<M-k>') to raw key strings
        for _, dir in ipairs({ 'up', 'down' }) do
            local key = opts.navigation[dir]
            if type(key) == 'number' then
                nav_keymaps[dir] = string.char(key)
            elseif type(key) == 'string' then
                nav_keymaps[dir] = keycode(key)
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



return M
