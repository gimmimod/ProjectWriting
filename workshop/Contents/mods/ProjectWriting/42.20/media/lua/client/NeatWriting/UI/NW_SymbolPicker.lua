--[[ ============================================================================
    NW_SymbolPicker - the symbol sheet.

    Vanilla's AddSymbol tool reads symbolsUI.selectedSymbol and goes straight for
    its .tex: with nothing selected it throws on a nil, which is exactly the
    crash the symbol button produced. So a symbol must be chosen before the tool
    is armed, and this is where that happens.

    The symbols come from MapSymbolDefinitions - the game's own, the two packs
    this mod bundles, and anything another mod registered. They are filed by
    NW_Categories, which sorts all three packs by what a symbol is rather than by
    who supplied it; a symbol from a mod we have never seen keeps the tab it
    declared, or lands under "Mods" if it declared none.

    Which packs are offered is a preference: see NW.packEnabled.

    Names come from NW_Names, not from the id: hovering a tile should say
    "Fire station", not "nw:axe2".
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "NeatWriting/NW_Categories"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Names"
require "NeatWriting/NW_Style"
require "NeatWriting/UI/NW_Tooltip"

NW_SymbolPicker = ISPanel:derive("NW_SymbolPicker")

local FONT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local MODS_TAB = "Mods"

-- Le misure di progetto, a scala 1. La tavola cresce con il pannello che la
-- ospita: e' dentro di lui, e una casella di trenta pixel dentro un pannello
-- al doppio della misura si vedrebbe subito che e' rimasta indietro.
local BASE = { cell = 30, gap = 4, pad = 8, tabGap = 3 }

local function round(v) return math.floor(v + 0.5) end

function NW_SymbolPicker:computeMetrics()
    local s = self.nwScale or 1
    local m = {}
    m.cell   = math.max(12, round(BASE.cell * s))
    m.gap    = math.max(2,  round(BASE.gap * s))
    m.pad    = math.max(3,  round(BASE.pad * s))
    m.tabGap = math.max(2,  round(BASE.tabGap * s))
    m.font, m.fontH = NW_Style.pickFont(FONT_SMALL * s)
    m.tabH = m.fontH + math.max(4, round(8 * s))
    self.metrics = m
end

--- La misura nuova, e la tavola si rifa'. La chiama il pannello quando la
--- maniglia si molla, non mentre la si tira: qui dentro ci sono centoquaranta
--- caselle, e rifarle a ogni pixel si sentirebbe.
function NW_SymbolPicker:setScale(s)
    if self.nwScale == s then return end
    self.nwScale = s
    self:computeMetrics()
    self:build()
end


-- ---------------------------------------------------------------------------
-- Reading the catalogue
-- ---------------------------------------------------------------------------

--- Every symbol the game knows, grouped by tab. Built once per open: mods can
--- register symbols at load time, so the list is not constant between sessions
--- but is certainly constant while the panel is up.
function NW_SymbolPicker.catalogue()
    local defs = MapSymbolDefinitions.getInstance()
    local groups, order = {}, {}

    local ok, count = pcall(function() return defs:getSymbolCount() end)
    if not ok or not count then return groups, order end

    for i = 0, count - 1 do
        local sym = defs:getSymbolByIndex(i)
        local id = sym and sym:getId()
        local path = sym and sym:getTexturePath()
        if sym and NW.packEnabled(id, path) then
            -- Our own taxonomy first. A symbol we have never seen keeps the tab
            -- its mod declared, and lands after ours.
            local tab = NW_Categories.tabOf(id)
            if not tab then
                local okTab, res = pcall(function() return sym:getTab() end)
                if okTab and res and res ~= "" then tab = res else tab = MODS_TAB end
            end

            groups[tab] = groups[tab] or {}
            groups[tab][#groups[tab] + 1] = {
                id = id,
                tex = path and getTexture(path) or nil,
            }
        end
    end

    -- Turning a pack off can leave a tab with one tile in it. Those are poured
    -- into the tab that collects them rather than shown as a tab of their own.
    NW_Categories.foldThin(groups)

    for tab in pairs(groups) do order[#order + 1] = tab end

    -- Known tabs in a known order, everything else after them by name: a mod
    -- we have never seen still lands somewhere sensible instead of first.
    table.sort(order, function(a, b)
        local ra, rb = NW.tabRank(a), NW.tabRank(b)
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    return groups, order
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

function NW_SymbolPicker:createChildren()
    self:computeMetrics()
    self:build()
end

--- Reads the catalogue and lays out tabs and tiles from it.
---
--- Called again whenever the answer would change - today that is the set of
--- symbol packs, which the player can switch without leaving the game.
function NW_SymbolPicker:build()
    if not self.metrics then self:computeMetrics() end
    local m = self.metrics
    local PAD, TAB_H, TAB_GAP = m.pad, m.tabH, m.tabGap

    NW_SymbolPicker.alive[self] = true
    for _, b in ipairs(self.tabButtons or {}) do self:removeChild(b) end
    for _, b in ipairs(self.cellButtons or {}) do self:removeChild(b) end

    self.builtWithPacks = NW.packSignature()
    self.groups, self.order = NW_SymbolPicker.catalogue()

    -- Keep the open tab across a rebuild when it survived the filter.
    local wanted = self.currentTab
    self.currentTab = self.order[1]
    for _, tab in ipairs(self.order) do
        if tab == wanted then self.currentTab = wanted break end
    end

    -- Nine categories do not fit on one line of a panel this wide, so the row
    -- wraps. Laying them out in a single line was what made the old tab strip
    -- run off the edge of the sheet.
    self.tabButtons = {}
    local x, y = PAD, PAD
    for _, tab in ipairs(self.order) do
        local label = NW.tabLabel(tab)
        local w = getTextManager():MeasureStringX(m.font, label) + math.max(8, round(14 * (self.nwScale or 1)))
        if x > PAD and x + w > self.width - PAD then
            x = PAD
            y = y + TAB_H + TAB_GAP
        end
        local b = ISButton:new(x, y, w, TAB_H, label, self, NW_SymbolPicker.onTab)
        b:initialise()
        b:instantiate()
        b:setDisplayBackground(false)
        b.internal = tab
        b.render = function() end
        self:addChild(b)
        self.tabButtons[#self.tabButtons + 1] = b
        x = x + w + TAB_GAP
    end

    self.gridY = y + TAB_H + PAD
    self.cellButtons = {}
    self:buildGrid()
end

function NW_SymbolPicker:perRow()
    local m = self.metrics
    return math.max(1, math.floor((self.width - m.pad * 2 + m.gap) / (m.cell + m.gap)))
end

function NW_SymbolPicker:buildGrid()
    local m = self.metrics
    local PAD, GAP, CELL = m.pad, m.gap, m.cell

    for _, b in ipairs(self.cellButtons) do self:removeChild(b) end
    self.cellButtons = {}

    local list = self.groups[self.currentTab] or {}
    local per = self:perRow()
    for i, sym in ipairs(list) do
        local col = (i - 1) % per
        local row = math.floor((i - 1) / per)
        local b = ISButton:new(PAD + col * (CELL + GAP), self.gridY + row * (CELL + GAP),
            CELL, CELL, "", self, NW_SymbolPicker.onSymbol)
        b:initialise()
        b:instantiate()
        b:setDisplayBackground(false)
        b.nwSymbol = sym
        b.render = function() end
        NW_Tooltip.attach(b, NW_Names.symbol(sym.id))
        self:addChild(b)
        self.cellButtons[#self.cellButtons + 1] = b
    end

    self.rows = math.max(1, math.ceil(#list / per))
    self.scrollRow = 0
    self:fitInto(self.room)
end

--- Show as many rows as  pixels allow. The panel grows to hold the sheet
--- rather than the sheet scrolling in a fixed window - scrolling only starts
--- when there is no screen left to grow into.
local DEFAULT_ROWS = 6   -- prima che qualcuno dica quanto spazio c'e'

function NW_SymbolPicker:fitInto(room)
    local m = self.metrics
    local PAD, GAP, CELL = m.pad, m.gap, m.cell

    self.room = room
    local rows = math.min(self.rows or 1, DEFAULT_ROWS)
    if room and room > 0 then
        rows = self.rows or 1
        local fits = math.floor((room - self.gridY - PAD + GAP) / (CELL + GAP))
        rows = math.max(1, math.min(rows, fits))
    end
    self.visibleRows = rows
    local maxScroll = math.max(0, (self.rows or 1) - rows)
    self.scrollRow = math.min(self.scrollRow or 0, maxScroll)
    -- Il GAP dopo l'ultima riga non c'e': senza il meno, l'altezza contava uno
    -- spazio che `fits` qui sopra aveva gia' concesso, e la tavola poteva
    -- venire quattro pixel piu' alta dello spazio che le era stato dato. Sotto
    -- l'ultima riga resta PAD, come sopra la prima.
    self:setHeight(self.gridY + rows * (CELL + GAP) - GAP + PAD)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function NW_SymbolPicker:onTab(button)
    self.currentTab = button.internal
    self:buildGrid()
end

function NW_SymbolPicker:onSymbol(button)
    self.selected = button.nwSymbol.id
    if self.onPick then self.onPick(button.nwSymbol) end
end

-- ---------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------

--- Every sheet alive right now, so a preference change can reach all of them.
---
--- Weak keys: the map screen is torn down and rebuilt over a session, and a
--- sheet nobody holds any more must not be kept alive by this list.
NW_SymbolPicker.alive = NW_SymbolPicker.alive or setmetatable({}, { __mode = "k" })

--- Rebuilds every sheet whose packs no longer match the preferences.
---
--- Called from NW_ModOptions the moment the options screen is confirmed. That
--- is a click handler, not a render pass, which is what makes it safe to add
--- and remove children here - see lesson 12.
---
--- Without this the switch only took effect the next time the sheet was shown,
--- and never at all if it was already open.
function NW_SymbolPicker.refreshAll()
    local want = NW.packSignature()
    for picker in pairs(NW_SymbolPicker.alive) do
        if picker.builtWithPacks and picker.builtWithPacks ~= want then
            pcall(function() picker:build() end)
        end
    end
end

--- The belt to refreshAll's braces: a sheet built while the options screen was
--- open, or one whose window was rebuilt since, catches up when it is shown.
function NW_SymbolPicker:setVisible(visible)
    if visible and self.builtWithPacks ~= nil
        and self.builtWithPacks ~= NW.packSignature() then
        self:build()
    end
    ISPanel.setVisible(self, visible)
end

function NW_SymbolPicker:prerender()
    local m = self.metrics
    local PAD, GAP, CELL = m.pad, m.gap, m.cell

    NW_Style.drawGroup(self, 0, 0, self.width, self.height)

    -- Rows move under the window rather than the window moving: the buttons
    -- are the hit areas, so they have to travel with what is drawn.
    local per = self:perRow()
    local off = (self.scrollRow or 0) * (CELL + GAP)
    for i, b in ipairs(self.cellButtons) do
        local col = (i - 1) % per
        local row = math.floor((i - 1) / per)
        b:setX(PAD + col * (CELL + GAP))
        b:setY(self.gridY + row * (CELL + GAP) - off)
    end
end

function NW_SymbolPicker:render()
    local m = self.metrics
    local GAP, CELL, TAB_H = m.gap, m.cell, m.tabH

    for _, b in ipairs(self.tabButtons) do
        local on = b.internal == self.currentTab
        local c = on and NW_Style.accent or NW_Style.dim
        if on then
            self:drawRect(b:getX(), b:getY() + b:getHeight() - 2, b:getWidth(), 2, 1,
                NW_Style.accent.r, NW_Style.accent.g, NW_Style.accent.b)
        end
        self:drawTextCentre(b.title or b.internal, b:getX() + b:getWidth() / 2,
            b:getY() + math.floor((TAB_H - m.fontH) / 2), c.r, c.g, c.b, 1, m.font)
    end

    local top = self.gridY
    local h = (self.visibleRows or 1) * (CELL + GAP)
    self:setStencilRect(0, top, self.width, h)
    for _, b in ipairs(self.cellButtons) do
        local sym = b.nwSymbol
        local on = sym.id == self.selected
        NW_Style.drawTile(self, b:getX(), b:getY(), CELL, CELL, on, b:isMouseOver())
        if sym.tex then
            local p = math.max(2, math.floor(CELL * 0.17))
            self:drawTextureScaled(sym.tex, b:getX() + p, b:getY() + p,
                CELL - p * 2, CELL - p * 2, 1, 0.92, 0.92, 0.92)
        end
    end
    self:clearStencilRect()

    -- Scrollbar: a thin rail, only when there is more sheet than window.
    if (self.rows or 1) > (self.visibleRows or 1) then
        local frac = (self.visibleRows) / self.rows
        local barH = math.max(18, h * frac)
        local at = (self.scrollRow or 0) / math.max(1, self.rows - self.visibleRows)
        local bx = self.width - 5
        self:drawRect(bx, top, 2, h, 0.35, 0.30, 0.30, 0.32)
        self:drawRect(bx, top + (h - barH) * at, 2, barH, 0.9,
            NW_Style.accent.r, NW_Style.accent.g, NW_Style.accent.b)
    end
end

function NW_SymbolPicker:onMouseDown(x, y) return true end
function NW_SymbolPicker:onMouseUp(x, y) return true end
function NW_SymbolPicker:onMouseWheel(del)
    local maxScroll = math.max(0, (self.rows or 1) - (self.visibleRows or 1))
    self.scrollRow = math.max(0, math.min(maxScroll, (self.scrollRow or 0) + del))
    return true
end

function NW_SymbolPicker:new(x, y, width, onPick)
    local o = ISPanel.new(self, x, y, width, 200)
    -- Il pannello che la ospita la corregge subito dopo, prima di costruirla:
    -- qui c'e' solo un valore sensato per il caso in cui qualcuno la apra da
    -- sola.
    o.nwScale = NW.panelScale()
    o.background = false
    o.moveWithMouse = false
    o.onPick = onPick
    o.selected = nil
    o.groups = {}
    o.order = {}
    return o
end
