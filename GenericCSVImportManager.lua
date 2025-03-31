------------------------------------------------------------------
-- Author: Stargrove
-- Purpose: Replace the #table# placeholder with the text in your CSV
--          file in text fields with a formatted HTML table.
------------------------------------------------------------------

-- Global variable to store the last formatted text field/control
local cFormattedText = nil

------------------------------------------------------------------
-- Function: onTabletopInit
-- Purpose: Initializes the sidebar button and starts a full database scan.
------------------------------------------------------------------
function onTabletopInit()
    local tButton = {
        sIcon = "csv_button",
        tooltipres = "sidebar_tooltip_csv2table",
        class = "GenericCSVImport",
    }

    if Session and Session.IsHost then
        DesktopManager.registerSidebarToolButton(tButton, false)
        Interface.onWindowOpened = onWindowOpen
        ChatManager.SystemMessage("Debug: Running full database scan for #table# placeholders...")
        fullDatabaseScan()
    else
        ChatManager.SystemMessage("Warning: Host session required to create sidebar button.")
    end
end

------------------------------------------------------------------
-- Function: fullDatabaseScan
-- Purpose: Recursively scans the entire `db.xml` structure and replaces #table#.
------------------------------------------------------------------
function fullDatabaseScan()
    local rootNode = DB.getRoot()
    if rootNode then
        --ChatManager.SystemMessage("Debug: Starting full database scan from root.")
        if searchAndReplaceTablePlaceholder(rootNode) then
            ChatManager.SystemMessage("Debug: #table# placeholder(s) found in database.")
        else
            ChatManager.SystemMessage("Debug: No #table# placeholders found in database.")
        end
    else
        ChatManager.SystemMessage("Error: Could not access the root of db.xml.")
    end
end

------------------------------------------------------------------
-- Function: onWindowOpen
-- Purpose: Calls a full database scan every time a new window is opened.
------------------------------------------------------------------
function onWindowOpen(w)
    local wClass = w.getClass()
    ChatManager.SystemMessage("Debug: Window opened - " .. wClass .. ", rescanning database...")
    fullDatabaseScan() -- Rescan every time a new window is opened
end

------------------------------------------------------------------
-- Function: searchAndReplaceTablePlaceholder
-- Purpose: Recursively searches for #table# placeholders in all formattedtext fields.
------------------------------------------------------------------
function searchAndReplaceTablePlaceholder(node, depth)
    depth = depth or 0
    local indent = string.rep("  ", depth)

    -- ChatManager.SystemMessage(indent .. "Debug: Searching in node -> " .. node.getName() .. " (type: " .. node.getType() .. ")")

    -- Check if node contains formatted text with #table#
    if node.getType() == "formattedtext" then
        local currentText = node.getValue()
        local s, e = string.find(currentText, "<p>#table#</p>")
        if s then
            ChatManager.SystemMessage(indent .. "Debug: Found #table# in node -> " .. node.getName())
            cFormattedText = node
            return true
        end
    end

    -- Recursively search all child nodes
    for name, child in pairs(node.getChildren()) do
        if searchAndReplaceTablePlaceholder(child, depth + 1) then
            return true
        end
    end

    return false
end


------------------------------------------------------------------
-- Function: parseCSVLine
-- Purpose: Parses a single line of CSV text into individual cells.
-- Parameters:
--  line - The line of text to parse.
--  sep  - The delimiter (default is a comma).
-- Returns:
--  A table of cell values from the line.
------------------------------------------------------------------
local function parseCSVLine(line, sep)
    local result = {}
    sep = sep or "," -- Default delimiter is a comma
    local pattern = string.format("([^%s]+)", sep) -- Pattern for splitting
    for value in string.gmatch(line, pattern) do
        table.insert(result, value) -- Add each value to the result table
    end
    return result
end

------------------------------------------------------------------
-- Function: createTableFromCSV
-- Purpose: Converts CSV text into an HTML table string.
-- Parameters:
--  csvText - The raw CSV text.
-- Returns:
--  A string representing an HTML table.
------------------------------------------------------------------
local function createTableFromCSV(csvText)
    local rows = {}
    for line in string.gmatch(csvText, "([^\n]*)\n?") do
        local row = parseCSVLine(line)
        table.insert(rows, row)
    end

    -- Build the HTML table string
    local tableText = "<table>"
    for _, row in ipairs(rows) do
        tableText = tableText .. "<tr>"
        for _, cell in ipairs(row) do
            tableText = tableText .. "<td>" .. escapeXML(cell) .. "</td>"
        end
        tableText = tableText .. "</tr>"
    end
    tableText = tableText .. "</table>"
    return tableText
end

------------------------------------------------------------------
-- Function: escapeXML
-- Purpose: Escapes special characters in text to ensure compatibility 
--          with XML and HTML formats. This prevents parsing errors.
-- Parameters:
--  value - The input string to be escaped.
-- Returns:
--  The escaped string, safe for XML and HTML usage.
------------------------------------------------------------------
local function escapeXML(value)
    if not value then return "" end -- Handle nil or empty input gracefully

    -- Replace special characters with their XML/HTML-safe equivalents
    value = string.gsub(value, "&", "&#38;")  -- Escape ampersand (&)
    value = string.gsub(value, "<", "&lt;")  -- Escape less-than (<)
    value = string.gsub(value, ">", "&gt;")  -- Escape greater-than (>)
    value = string.gsub(value, "\"", "&quot;") -- Escape double quote (")
    value = string.gsub(value, "'", "&apos;") -- Escape single quote (')
    value = string.gsub(value, "%%", "&#37;")  -- Escape percent sign (%)
    value = string.gsub(value, "%+", "&#43;")  -- Escape plus sign (+)

    return value
end


------------------------------------------------------------------
-- Function: onImportCSV
-- Purpose: Replaces the #table# placeholder with the formatted 
--          table in the current formatted text field.
-- Parameters:
--  csvText - The raw CSV text.
------------------------------------------------------------------
function onImportCSV(csvText)
    if not cFormattedText then
        ChatManager.SystemMessage("No #table# placeholder found in the current window.")
        return
    end

    local tableText = createTableFromCSV(csvText)
    local currentText = cFormattedText.getValue()
    local newText = string.gsub(currentText, "<p>#table#</p>", tableText, 1)
    cFormattedText.setValue(newText)
    ChatManager.SystemMessage("CSV imported successfully!")
end

------------------------------------------------------------------
-- Function: onCSVFileSelection
-- Purpose: Reads the selected CSV file and processes it.
-- Parameters:
--  result - The result of the file selection dialog.
--  sPath  - The path to the selected file.
------------------------------------------------------------------
function onCSVFileSelection(result, sPath)
    if result ~= "ok" then return end

    local sContents = File.openTextFile(sPath)
    if not sContents then
        ChatManager.SystemMessage("Failed to open the selected CSV file.")
        return
    end

    local tContents = Utility.decodeCSV(sContents)
    if not tContents then
        ChatManager.SystemMessage("Failed to decode CSV content.")
        return
    end

    local sTable = "<table>"
    for _, row in ipairs(tContents) do
        sTable = sTable .. "<tr>"
        for _, cell in ipairs(row) do
            sTable = sTable .. "<td>" .. escapeXML(cell) .. "</td>"
        end
        sTable = sTable .. "</tr>"
    end
    sTable = sTable .. "</table>"

    if cFormattedText then
        local sValue = cFormattedText.getValue()
        local success, newValue = pcall(function()
            return string.gsub(sValue, "<p>#table#</p>", sTable, 1)
        end)
        if success then
            cFormattedText.setValue(newValue)
            ChatManager.SystemMessage("CSV imported successfully!")
        else
            ChatManager.SystemMessage("Error: Failed to replace placeholder.")
        end
    else
        ChatManager.SystemMessage("No formatted text field with #table# found.")
    end
end
