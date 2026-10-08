--[[ ============================================================================
    NW_MapKey - the map legend, in the family's clothes.

    Vanilla draws it as a flat black rectangle with a centred title and eight
    swatch-and-label rows, sizing itself while it paints. It is restyled in
    place rather than rebuilt: same object, same eight entries read from the
    same place, our surfaces around them.

    The one behavioural change is the header: it gets a title bar with an icon
    and a close button, so the legend is dismissed the way every other Neat
    panel is instead of only by the button that opened it.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/Maps/ISWorldMapKey"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Style"

local FONT_SMALL  = getTextManager():getFontHeight(UIFont.Small)
local FONT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 10
local ROW_GAP = 4
local HEADER_H = math.floor(FONT_MEDIUM * 1.5)

--- Vanilla's own title for its own panel: already translated everywhere. Ours
--- only stands in if a build ever drops the key.
local function nwLegendTitle()
    local text = getText("IGUI_Map_Key")
    if text and text ~= "" and text ~= "IGUI_Map_Key" then return text end
    return getText("IGUI_NW_Legend")
end

--- Vanilla measures the panel while drawing it, which is why its width jumps
--- about on the first frames. Measured once, up front, from the same strings.
local function measure(self)
    local swatchW = math.max(FONT_SMALL * 2 + 12, 56)
    local swatchH = math.max(FONT_SMALL + 4, 26)
    local widest = 0
    for i = 1, 8 do
        local label = getText("IGUI_Map_" .. (self.key[i] or ""))
        widest = math.max(widest, getTextManager():MeasureStringX(UIFont.Small, label))
    end
    local titleW = getTextManager():MeasureStringX(UIFont.Medium, nwLegendTitle())
    return math.max(PAD * 2 + swatchW + PAD + widest,
                    PAD * 2 + titleW),
           HEADER_H + PAD + 8 * (swatchH + ROW_GAP) - ROW_GAP + PAD,
           swatchW, swatchH
end

ISWorldMapKey.createChildren_prepatch_neatwriting = ISWorldMapKey.createChildren
function ISWorldMapKey:createChildren()
    self:createChildren_prepatch_neatwriting()
    if NW.vanillaMap() then return end

    -- No close button: the map bar's legend button is what opens and shuts this,
    -- and one control that does both is clearer than a second one that only
    -- shuts it.
    local w, h, sw, sh = measure(self)
    self.nwSwatchW, self.nwSwatchH = sw, sh
    self:setWidth(w)
    self:setHeight(h)
end

ISWorldMapKey.prerender_prepatch_neatwriting = ISWorldMapKey.prerender
function ISWorldMapKey:prerender()
    if NW.vanillaMap() then return self:prerender_prepatch_neatwriting() end
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
    self:drawText(nwLegendTitle(), tx,
        math.floor((HEADER_H - FONT_MEDIUM) / 2),
        NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, UIFont.Medium)
end

ISWorldMapKey.render_prepatch_neatwriting = ISWorldMapKey.render
function ISWorldMapKey:render()
    if NW.vanillaMap() then return self:render_prepatch_neatwriting() end
    local path = self.keyImagePath
    if getCore():getOptionColorblindPatterns() then
        path = path .. "Colorblind Patterns/"
    end

    local sw, sh = self.nwSwatchW, self.nwSwatchH
    local y = HEADER_H + PAD
    for i = 1, 8 do
        local name = self.key[i]
        if name then
            local tex = getTexture(path .. "Key_" .. name .. (self.iso and "_iso" or "") .. ".png")
            -- Drawn bare: a frame around every colour is the first thing the eye
            -- catches, and a colour key is meant to be read as colour.
            if tex then
                self:drawTextureScaled(tex, PAD, y, sw, sh, 1, 1, 1, 1)
            end
            self:drawText(getText("IGUI_Map_" .. name), PAD + sw + PAD,
                y + math.floor((sh - FONT_SMALL) / 2),
                NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, UIFont.Small)
            y = y + sh + ROW_GAP
        end
    end
end

-- Vanilla non li definisce - la sua legenda i clic li riceve dalla mappa, non
-- da se' - quindi qui non c'e' niente da restituire: con la mappa lasciata al
-- gioco si torna a quello che ISPanel fa di suo.
function ISWorldMapKey:onMouseDown(x, y)
    if NW.vanillaMap() then return ISPanel.onMouseDown(self, x, y) end
    return true
end

function ISWorldMapKey:onMouseUp(x, y)
    if NW.vanillaMap() then return ISPanel.onMouseUp(self, x, y) end
    return true
end
