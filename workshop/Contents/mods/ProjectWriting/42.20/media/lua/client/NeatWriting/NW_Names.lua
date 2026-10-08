--[[ ============================================================================
    NW_Names - what a symbol is called.

    MapSymbolDefinitions only knows ids, and ids are written for code:
    "ArrowNorthEast", "AmmSSign_1", "nw:pipeWrench". Showing those on hover is
    how the sheet ended up reading like a listing rather than a set of symbols.

    So every symbol gets a name, looked up as IGUI_NW_Sym_<id>, with the id
    sanitised to letters, digits and underscores. Three families are named in
    full and translated:

      * vanilla's own 51
      * the 46 this mod adds
      * AddMoreMapSymbols' 95, so that mod's symbols read properly too

    Anything else - a symbol from a mod we have never seen - falls through to
    prettify(), which turns the id into something readable rather than leaving
    it raw. It will be in English, but it will be a phrase and not a code.

    Answers are cached: the sheet asks for the same names on every frame it is
    hovered, and getText is not free.
============================================================================ ]]--

if isServer() then return end

NW_Names = NW_Names or {}
local N = NW_Names

local cache = {}

--- Ids carry characters a translation key cannot: "nw:axe" becomes "nw_axe".
local function keyFor(id)
    return "IGUI_NW_Sym_" .. tostring(id):gsub("[^%w]", "_")
end

--- Last resort for symbols nobody has named. Splits camelCase, turns separators
--- into spaces and capitalises the first letter: "ArrowNorthEast" reads as
--- "Arrow north east" instead of shouting its own id.
function N.prettify(id)
    local s = tostring(id or "")
    s = s:gsub("^[%a]+:", "")                  -- a mod prefix, if there is one
    s = s:gsub("(%l)(%u)", "%1 %2")
    s = s:gsub("[_%-%.]+", " ")
    s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return tostring(id) end
    return s:sub(1, 1):upper() .. s:sub(2):lower()
end

--- The name to show for a symbol id.
function N.symbol(id)
    if not id then return "" end
    local hit = cache[id]
    if hit then return hit end

    local key = keyFor(id)
    local text = getText(key)
    if not text or text == "" or text == key then
        text = N.prettify(id)
    end
    cache[id] = text
    return text
end

--- The language can change without the game restarting.
function N.clear()
    cache = {}
end

return NW_Names
