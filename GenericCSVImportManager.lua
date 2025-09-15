------------------------------------------------------------------
-- Author: Stargrove
-- Purpose: Replace the #table# placeholder with the text in your CSV
--          file in text fields with a formatted HTML table.
-- Notes:
--   * escapeXML handles bullets/quotes/dashes (incl. Excel mojibake).
--   * Placeholder match is tolerant: <p ...>#table#</p> (+ whitespace/NBSP).
--   * Replacement success is verified before announcing "imported".
------------------------------------------------------------------

-- Global variable to store the last formatted text field/control
local cFormattedText = nil

-- Tolerant pattern for the #table# paragraph (case-insensitive <p>, attrs allowed,
-- spaces or NBSP around #table# allowed)
local PLACEHOLDER_PATTERN = "<[Pp][^>]*>%s*#table#%s*</[Pp]>"

------------------------------------------------------------------
-- Function: onTabletopInit
-- Purpose : Initializes the sidebar button and starts a full database scan.
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
-- Purpose : Recursively scans the entire db.xml structure and finds #table#.
------------------------------------------------------------------
function fullDatabaseScan()
    local rootNode = DB.getRoot()
    if rootNode then
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
-- Purpose : Calls a full database scan every time a new window is opened.
------------------------------------------------------------------
function onWindowOpen(w)
    local wClass = w.getClass()
    ChatManager.SystemMessage("Debug: Window opened - " .. wClass .. ", rescanning database...")
    fullDatabaseScan()
end

------------------------------------------------------------------
-- Function: searchAndReplaceTablePlaceholder
-- Purpose : Recursively searches for #table# placeholders in all formattedtext fields.
-- Notes   : Uses tolerant pattern so <p ...>#table#</p> is matched.
------------------------------------------------------------------
function searchAndReplaceTablePlaceholder(node, depth)
    depth = depth or 0

    if node.getType and node.getType() == "formattedtext" then
        local currentText = node.getValue()
        if currentText and string.find(currentText, PLACEHOLDER_PATTERN) then
            cFormattedText = node
            return true
        end
    end

    if node.getChildren then
        for _, child in pairs(node.getChildren()) do
            if searchAndReplaceTablePlaceholder(child, (depth + 1)) then
                return true
            end
        end
    end

    return false
end

------------------------------------------------------------------
-- Function: createTableFromCSV
-- Purpose : Converts CSV text into an HTML table string.
-- Notes   : Uses Fantasy Grounds' Utility.decodeCSV for robust parsing.
------------------------------------------------------------------
local function createTableFromCSV(csvText)
    local tContents = Utility.decodeCSV(csvText) or {}

    local tableText = "<table>"
    for _, row in ipairs(tContents) do
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
-- Function: escapeXML (minimal + robust)
-- Purpose : Escape XML chars, and normalize common Unicode/mojibake chars:
--           • bullets, ’ ‘ smart apostrophes, – — dashes.
-- Order   : 1) Escape XML-reserved chars
--           2) Map problem characters to numeric entities
-- Rationale: Escaping first avoids double-escaping entities we create.
------------------------------------------------------------------
local function escapeXML(value)
    if not value then return "" end

    -- 1) Escape XML-reserved characters
    value = value:gsub("&", "&#38;")
                 :gsub("<", "&lt;")
                 :gsub(">", "&gt;")
                 :gsub('"', "&quot;")
                 :gsub("'", "&apos;")
                 :gsub("%%", "&#37;")
                 :gsub("%+", "&#43;")

    -- 2) Normalize “problem” characters to numeric entities

    -- Bullets
    value = value
        :gsub("•",   "&#8226;")  -- UTF-8 bullet (U+2022)
        :gsub("â€¢", "&#8226;")  -- Excel mojibake bullet
        :gsub("\149","&#8226;")  -- CP1252 bullet (0x95)

    -- Smart apostrophes / single quotes
    value = value
        :gsub("’",   "&#8217;")  -- U+2019
        :gsub("‘",   "&#8216;")  -- U+2018
        :gsub("â€™","&#8217;")  -- mojibake ’
        :gsub("â€˜","&#8216;")  -- mojibake ‘
        :gsub("\146","&#8217;") -- CP1252 ’ (0x92)
        :gsub("\145","&#8216;") -- CP1252 ‘ (0x91)

    -- Dashes
    value = value
        :gsub("–",   "&#8211;")  -- en dash U+2013
        :gsub("—",   "&#8212;")  -- em dash U+2014
        :gsub("â€“","&#8211;")  -- mojibake –
        :gsub("â€”","&#8212;")  -- mojibake —
        :gsub("\150","&#8211;") -- CP1252 – (0x96)
        :gsub("\151","&#8212;") -- CP1252 — (0x97)

    return value
end

------------------------------------------------------------------
-- Helper: replacePlaceholderOnce
-- Purpose: Replace the FIRST paragraph that contains exactly "#table#"
--          (ignoring surrounding spaces and NBSP) with the provided table HTML.
-- Notes  : Uses function replacement to avoid '%' issues in replacement text.
------------------------------------------------------------------
local function replacePlaceholderOnce(html, tableHTML)
    local replaced = false

    local function trimInner(s)
        -- Convert NBSP (U+00A0) to regular space, then trim
        s = s:gsub("\194\160", " ")
        return (s:gsub("^%s*(.-)%s*$", "%1"))
    end

    local function repl(attr, inner)
        if (not replaced) and trimInner(inner) == "#table#" then
            replaced = true
            return tableHTML
        end
        return "<p" .. attr .. ">" .. inner .. "</p>"
    end

    -- Match <p ...> ... </p> in a tolerant, case-insensitive way
    local new = html:gsub("<[Pp]([^>]*)>(.-)</[Pp]>", repl)
    return new, (replaced and 1 or 0)
end

------------------------------------------------------------------
-- Function: onImportCSV
-- Purpose : Replaces the #table# placeholder with the formatted table
--           in the current formatted text field (paste/string path).
------------------------------------------------------------------
function onImportCSV(csvText)
    if not cFormattedText then
        ChatManager.SystemMessage("No #table# placeholder found in the current window.")
        return
    end

    local tableText = createTableFromCSV(csvText)
    local currentText = cFormattedText.getValue()

    -- Tolerant, verified replacement
    local newText, count = replacePlaceholderOnce(currentText, tableText)
    if count > 0 then
        cFormattedText.setValue(newText)
        ChatManager.SystemMessage("CSV imported successfully! (1 placeholder replaced)")
    else
        ChatManager.SystemMessage("Placeholder not found or not in a standalone paragraph.")
    end
end

------------------------------------------------------------------
-- Function: onCSVFileSelection
-- Purpose : Reads the selected CSV file and processes it (file path path).
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

    if not cFormattedText then
        ChatManager.SystemMessage("No formatted text field with #table# found.")
        return
    end

    local sValue = cFormattedText.getValue()
    local newValue, count = replacePlaceholderOnce(sValue, sTable)
    if count > 0 then
        cFormattedText.setValue(newValue)
        ChatManager.SystemMessage("CSV imported successfully! (1 placeholder replaced)")
    else
        ChatManager.SystemMessage("Placeholder not found or not in a standalone paragraph.")
    end
end
