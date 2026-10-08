--[[ ============================================================================
    NW_Legend - the building-colour legend, ours and in the family's clothes.

    Two legends exist on the world map and this file settles which one shows:

      * vanilla's ISWorldMapKey, restyled in NW_MapKey
      * Map Legend UI's own window (NikGamer), which hides vanilla's from inside
        its render and puts up a flat black panel of its own

    That hiding is why restyling vanilla's appeared to do nothing while that mod
    was on. So this draws the same eight building categories ourselves and
    stands down when Map Legend UI is not installed - in which case NW_MapKey's
    restyled vanilla legend is the one on screen.

    Names and swatches come from the game, not from us: ISWorldMapKey's own
    IGUI_Map_* keys and its own textures, colourblind patterns included. That is
    what makes this legend read in every language the game ships without our
    translating a word of it, and what makes the two legends identical whichever
    one is on screen.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/Maps/ISWorldMap"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Style"

NW_Legend = ISPanel:derive("NW_Legend")

local FONT_SMALL  = getTextManager():getFontHeight(UIFont.Small)
local FONT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 10
local ROW_GAP = 3
-- The same swatch vanilla draws, at the same size: the two legends have to be
-- the same legend, not a family resemblance.
local SWATCH_W = math.max(FONT_SMALL * 2 + 12, 56)
local SWATCH_H = math.max(FONT_SMALL + 4, 26)
local ROW_H = SWATCH_H
local HEADER_H = math.floor(FONT_MEDIUM * 1.5)

--- The eight categories, in ISWorldMapKey's own order. These are the game's
--- names, so they are already translated everywhere.
local ROWS = {
    "Community", "Hospitality", "Industrial", "Medical",
    "Parks", "Residential", "RestaurantsEntertainment", "RetailCommercial",
}

local SWATCH_PATH = "media/textures/worldMap/"

--- Vanilla's own swatch, colourblind patterns included.
local function swatch(name)
    local path = SWATCH_PATH
    if getCore():getOptionColorblindPatterns() then
        path = path .. "Colorblind Patterns/"
    end
    return getTexture(path .. "Key_" .. name .. ".png")
end

--- The panel's title. Vanilla's key first: it is the same legend, and it is
--- translated in every language the game ships.
local function title()
    local text = getText("IGUI_Map_Key")
    if text and text ~= "" and text ~= "IGUI_Map_Key" then return text end
    return getText("IGUI_NW_Legend")
end

function NW_Legend:createChildren()
    local widest = 0
    for _, name in ipairs(ROWS) do
        widest = math.max(widest,
            getTextManager():MeasureStringX(UIFont.Small, getText("IGUI_Map_" .. name)))
    end
    local titleW = getTextManager():MeasureStringX(UIFont.Medium, title())

    -- No close button: the legend is a panel you flip on and off from the map
    -- bar, and it is the same button either way. A red X in the corner made it
    -- look like a window with two ways to shut it, one of which the button then
    -- disagreed with.
    self:setWidth(math.max(PAD * 2 + SWATCH_W + PAD + widest + PAD,
                           PAD * 2 + titleW + PAD))
    self:setHeight(HEADER_H + PAD + #ROWS * (ROW_H + ROW_GAP) - ROW_GAP + PAD)
end

function NW_Legend:prerender()
    NW_Style.drawWindow(self, 0, 0, self.width, self.height, HEADER_H)

    local pad = NW_Style.headerPadding(HEADER_H)
    local iconSize = NW_Style.headerIconSize(HEADER_H)
    local tx = pad
    local icon = NW_Style.tex(NW.ICONS .. "Legend.png")
    if icon then
        self:drawTextureScaled(icon, pad, math.floor((HEADER_H - iconSize) / 2),
            iconSize, iconSize, 1, NW_Style.text.r, NW_Style.text.g, NW_Style.text.b)
        tx = pad + iconSize + NW_Style.headerGap(HEADER_H)
    end
    self:drawText(title(), tx,
        math.floor((HEADER_H - FONT_MEDIUM) / 2),
        NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, UIFont.Medium)
end

function NW_Legend:render()
    local y = HEADER_H + PAD
    for _, name in ipairs(ROWS) do
        local tex = swatch(name)
        -- The swatch is drawn bare. It was sitting on a tile so a pale colour
        -- would still read as a chip, but the frame around every colour is what
        -- the eye caught first - and a colour key is meant to be read as colour.
        if tex then
            self:drawTextureScaled(tex, PAD, y, SWATCH_W, SWATCH_H, 1, 1, 1, 1)
        end
        self:drawText(getText("IGUI_Map_" .. name), PAD + SWATCH_W + PAD,
            y + math.floor((SWATCH_H - FONT_SMALL) / 2),
            NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, UIFont.Small)
        y = y + ROW_H + ROW_GAP
    end
end

function NW_Legend:onMouseDown(x, y) return true end
function NW_Legend:onMouseUp(x, y) return true end

function NW_Legend:new(x, y)
    local o = ISPanel.new(self, x, y, 220, 200)
    o.background = false
    o.moveWithMouse = false
    return o
end

-- ---------------------------------------------------------------------------
-- Taking over from Map Legend UI
-- ---------------------------------------------------------------------------

local function mapLegendUIActive()
    return rawget(_G, "mapLegendWindow") ~= nil
end

ISWorldMap.createChildren_prepatch_nwlegend = ISWorldMap.createChildren
function ISWorldMap:createChildren()
    self:createChildren_prepatch_nwlegend()
    if NW.vanillaMap() then return end
    if not mapLegendUIActive() then return end

    -- Its window and its button both stand down: ours replaces the first, and
    -- the map bar's legend button replaces the second.
    if self.mapLegend then
        self.mapLegend:setVisible(false)
        self.mapLegend.prerender = function(w) w:setVisible(false) end
    end
    if self.legendButton then
        self.legendButton:setVisible(false)
        self.legendButton.prerender = function(b) b:setVisible(false) end
    end

    local legend = NW_Legend:new(NW.PAD, NW.PAD)
    legend:initialise()
    legend:instantiate()
    self:addChild(legend)
    legend:setVisible(false)
    self.nwLegend = legend
end
