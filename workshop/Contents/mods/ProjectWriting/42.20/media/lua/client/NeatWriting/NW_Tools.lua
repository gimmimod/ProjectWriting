--[[ ============================================================================
    NW_Tools - what the player can actually write and erase with.

    The panel shows the real items out of the inventory, not abstract colours:
    a pen you own, with its own icon, is what you pick up to write. Tags decide
    which colours an item can lay down, so a pen from someone else's mod works
    without us ever naming it; the type lists only catch items shipped untagged.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Config"

NW_Tools = NW_Tools or {}
local T = NW_Tools

-- ---------------------------------------------------------------------------
-- Tag plumbing. Building an ItemTag can throw on a name the game does not
-- know, so every call is wrapped: a bad tag must never take the panel down.
-- ---------------------------------------------------------------------------

--- Vanilla builds these from the bare item name - ItemTag.get(ResourceLocation
--- .of("Pen")) - while the scripts spell the tag "base:pen"
--- (ISWorldMapSymbols:checkInventory). Which form ResourceLocation wants is not
--- something to guess at, so try both and keep whichever answers.
local _tagCache = {}
local function tagOf(name)
    if not (ItemTag and ResourceLocation) then return nil end
    local hit = _tagCache[name]
    if hit ~= nil then return hit or nil end

    local forms = { name }
    local bare = string.match(name, "^base:(.+)$")
    if bare then
        forms[#forms + 1] = bare
        -- "base:redpen" -> "RedPen": the spelling colorButtonInfo uses.
        forms[#forms + 1] = (bare:gsub("^%l", string.upper))
    end

    for _, form in ipairs(forms) do
        local ok, tag = pcall(function() return ItemTag.get(ResourceLocation.of(form)) end)
        if ok and tag then
            _tagCache[name] = tag
            return tag
        end
    end
    _tagCache[name] = false
    return nil
end

local function itemHasTag(item, name)
    local tag = tagOf(name)
    if not (item and tag) then return false end
    local ok, res = pcall(function() return item:hasTag(tag) end)
    return ok and res == true
end

local function bareType(item)
    local ok, t = pcall(function() return item:getType() end)
    return ok and t or nil
end

local function typeIsIn(item, types)
    local t = bareType(item)
    if not t then return false end
    for _, want in ipairs(types) do
        if t == want then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Collecting
-- ---------------------------------------------------------------------------

--- Describes one item as a writing tool: which inks it lays down, whether it
--- can erase. Nil when the item is neither.
local function describe(item)
    local entry = { inks = {} }
    for _, ink in ipairs(NW.INKS) do
        if itemHasTag(item, ink.tag) or typeIsIn(item, ink.types) then
            entry.inks[#entry.inks + 1] = ink.id
        end
    end
    entry.isEraser = itemHasTag(item, NW.ERASER.tag) or typeIsIn(item, NW.ERASER.types)
    -- Tagged as a writing implement but with no colour of its own: black.
    if #entry.inks == 0 and not entry.isEraser and itemHasTag(item, NW.WRITE_TAG) then
        entry.inks[1] = NW.INKS[1].id
    end
    if #entry.inks == 0 and not entry.isEraser then return nil end

    entry.item = item
    entry.type = bareType(item)
    local ok, name = pcall(function() return item:getName() end)
    entry.name = ok and name or entry.type
    ok, entry.tex = pcall(function() return item:getTex() end)
    if not ok then entry.tex = nil end
    return entry
end

--- getAllTagRecurse needs an ArrayList and was silently returning nothing here,
--- which is why a pen in the bag showed as "nothing to write with".
--- getFirstTagRecurse is what vanilla actually leans on (ISGarmentUI:181), and
--- one item per tag is all the strip needs: it shows a kind of pen, not each pen.
local function collectByTag(inv, tagName, into, seen)
    local tag = tagOf(tagName)
    if not tag then return end
    local ok, item = pcall(function() return inv:getFirstTagRecurse(tag) end)
    if not (ok and item) then return end
    local t = bareType(item)
    if not t or seen[t] then return end
    local entry = describe(item)
    if entry then
        seen[t] = true
        into[#into + 1] = entry
    end
end

--- The net under the tags. Three lookups because which one a build answers on
--- is not worth guessing: getItemFromType is what ISGarmentUI reaches for,
--- getFirstTypeRecurse what the context menus use, and the full "Base.X" form
--- is needed by some of them.
local function findByType(inv, typeName)
    local tries = {
        function() return inv:getItemFromType(typeName, true, true) end,
        function() return inv:getFirstTypeRecurse(typeName) end,
        function() return inv:getFirstTypeRecurse("Base." .. typeName) end,
    }
    for _, try in ipairs(tries) do
        local ok, item = pcall(try)
        if ok and item then return item end
    end
    return nil
end

local function collectByType(inv, typeName, into, seen)
    if seen[typeName] then return end
    local item = findByType(inv, typeName)
    if not item then return end
    local entry = describe(item)
    if entry then
        seen[typeName] = true
        into[#into + 1] = entry
    end
end

--- Every writing tool the player is carrying, one entry per item type.
--- Order is fixed - inks in palette order, erasers last - so a tool never
--- moves under the cursor because something was picked up or used up.
function T.scanTools(playerObj)
    local out, seen = {}, {}
    local inv = playerObj and playerObj:getInventory()
    if not inv then return out end

    for _, ink in ipairs(NW.INKS) do
        collectByTag(inv, ink.tag, out, seen)
    end
    collectByTag(inv, NW.ERASER.tag, out, seen)
    -- Anything tagged as a writing implement without saying which colour: it
    -- still belongs in the strip, and describe() gives it black.
    collectByTag(inv, NW.WRITE_TAG, out, seen)

    -- Net for items that ship without tags.
    for _, ink in ipairs(NW.INKS) do
        for _, ty in ipairs(ink.types) do collectByType(inv, ty, out, seen) end
    end
    for _, ty in ipairs(NW.ERASER.types) do collectByType(inv, ty, out, seen) end

    table.sort(out, function(a, b)
        local ae = a.isEraser and #a.inks == 0
        local be = b.isEraser and #b.inks == 0
        if ae ~= be then return be end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

-- ---------------------------------------------------------------------------
-- Questions the panel asks
-- ---------------------------------------------------------------------------

function T.hasEraser(playerObj)
    for _, tool in ipairs(T.scanTools(playerObj)) do
        if tool.isEraser then return true end
    end
    return false
end

function T.canWrite(playerObj)
    for _, tool in ipairs(T.scanTools(playerObj)) do
        if #tool.inks > 0 then return true end
    end
    return false
end

--- A blank sheet the player can spend, in the inventory or within reach.
---
--- THE LOOSE SHEET IS `SheetPaper2`, WITH THE TWO. Plain `SheetPaper` does not
--- exist in B42 at all, and looking for it returns nil every time: the crop
--- button never appeared, and from outside it looked like it had never been
--- built. No error, no log line - the item lookup simply answers nothing.
--- `oggetti.js` exists because of this, and the `--@oggetti` mark is what tells
--- it this table holds item names.
---
--- The loose sheet and nothing else: `Notebook` and `Journal` are bound, and
--- tearing a page out of one to make a map is a different action with a
--- different cost. Inventing it silently would surprise whoever was keeping
--- that notebook for something.
---
--- ALSO WHAT IS NEARBY, not only what is carried. You draw a map standing at a
--- table, and the sheet is on the table - looking only under the player's feet
--- would tell someone they have no paper while they are staring at it.
local PAPER = { "SheetPaper2" }  --@oggetti

--- I contenitori a portata di mano: quello addosso, piu' quelli sui nove
--- quadrati attorno. Nove e non uno perche' si scrive stando davanti a un
--- tavolo, non sopra: il foglio e' sul quadrato accanto, e cercarlo solo sotto
--- i piedi direbbe "non hai carta" a chi ce l'ha davanti.
local function nearbyContainers(playerObj)
    local out = {}
    local sq
    pcall(function() sq = playerObj:getCurrentSquare() end)
    if not sq then return out end
    local cell
    pcall(function() cell = getCell() end)
    if not cell then return out end

    for dx = -1, 1 do
        for dy = -1, 1 do
            local near
            pcall(function() near = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ()) end)
            if near then
                pcall(function()
                    local objs = near:getObjects()
                    for i = 0, objs:size() - 1 do
                        local c = objs:get(i):getContainer()
                        if c then out[#out + 1] = c end
                    end
                end)
            end
        end
    end
    return out
end

function T.findPaper(playerObj)
    if not playerObj then return nil end
    local places = {}
    local inv
    pcall(function() inv = playerObj:getInventory() end)
    if inv then places[1] = inv end
    for _, c in ipairs(nearbyContainers(playerObj)) do places[#places + 1] = c end

    -- Prima addosso e poi intorno, un nome per volta: chi ha il foglio in tasca
    -- non deve vedersi consumare quello sul tavolo di qualcun altro.
    for _, where in ipairs(places) do
        for _, name in ipairs(PAPER) do
            local item = findByType(where, name)
            if item then return item end
        end
    end
    return nil
end

function T.hasPaper(playerObj)
    return T.findPaper(playerObj) ~= nil
end

--- Illiterate characters can place symbols but not read or write words.
function T.isIlliterate(playerObj)
    if not playerObj then return false end
    local ok, res = pcall(function()
        return playerObj:hasTrait(CharacterTrait.ILLITERATE)
    end)
    return ok and res == true
end
