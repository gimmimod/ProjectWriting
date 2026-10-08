--[[ ============================================================================
    NW_Slider - the draggable line under the pen.

    ISSliderPanel is vanilla furniture and looks it, so this is ours: a thin
    rail, an orange fill up to the handle, and a preview of the actual stroke
    beside it - you set a brush width by seeing the brush, not by reading a
    number.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "NeatWriting/NW_Style"

NW_Slider = ISPanel:derive("NW_Slider")

local RAIL = 3
local KNOB = 13

--- La scala di chi lo ospita, 1 per chi non ne ha una: il pannello Writing si
--- tira per l'angolo e la sua manopola deve crescere con lui, il pannello
--- delle opzioni della mappa non si tira e resta com'e'.
function NW_Slider:scale()
    return self.nwScale or 1
end

function NW_Slider:knobSize()
    return math.max(8, math.floor(KNOB * self:scale() + 0.5))
end

function NW_Slider:railSize()
    return math.max(2, math.floor(RAIL * self:scale() + 0.5))
end

--- Quanto spazio si tiene l'anteprima a destra.
function NW_Slider:preview()
    return math.floor((self.previewW or 0) * self:scale())
end

function NW_Slider:setValue(v, quiet)
    local was = self.value
    self.value = math.max(self.minValue, math.min(self.maxValue, v))
    if not quiet and self.value ~= was and self.onChange then
        self.onChange(self.target, self.value, self)
    end
end

function NW_Slider:fraction()
    local span = self.maxValue - self.minValue
    if span <= 0 then return 0 end
    return (self.value - self.minValue) / span
end

--- Rail runs inset by half a knob at each end, so the handle never hangs off.
function NW_Slider:railBounds()
    -- The rail stops a full knob before the preview: at maximum width the
    -- stroke is as tall as its value, and the two used to overlap.
    local knob = self:knobSize()
    local x0 = knob / 2
    return x0, self.width - self:preview() - knob * 1.5
end

function NW_Slider:valueAt(mouseX)
    local x0, w = self:railBounds()
    if w <= 0 then return self.minValue end
    local f = math.max(0, math.min(1, (mouseX - x0) / w))
    local raw = self.minValue + f * (self.maxValue - self.minValue)
    if self.step and self.step > 0 then
        raw = math.floor(raw / self.step + 0.5) * self.step
    end
    return raw
end

function NW_Slider:onMouseDown(x, y)
    self.dragging = true
    self:setValue(self:valueAt(x))
    return true
end

function NW_Slider:onMouseMove(dx, dy)
    if self.dragging then self:setValue(self:valueAt(self:getMouseX())) end
    return true
end

function NW_Slider:onMouseMoveOutside(dx, dy)
    if self.dragging then self:setValue(self:valueAt(self:getMouseX())) end
    return true
end

function NW_Slider:onMouseUp(x, y)
    self.dragging = false
    return true
end

function NW_Slider:onMouseUpOutside(x, y)
    self.dragging = false
    return true
end

function NW_Slider:render()
    local x0, w = self:railBounds()
    local cy = math.floor(self.height / 2)
    local f = self:fraction()
    local kx = x0 + w * f
    local RAIL = self:railSize()
    local KNOB = self:knobSize()

    -- Rail: dark behind, accent up to the handle.
    self:drawRect(x0, cy - RAIL / 2, w, RAIL, 1, 0.10, 0.10, 0.11)
    self:drawRect(x0, cy - RAIL / 2, w * f, RAIL, 1,
        NW_Style.accent.r, NW_Style.accent.g, NW_Style.accent.b)

    -- Round handle: a square knob on a round rail reads as a bug, not a style.
    local a = self:isMouseOver() and 1.0 or 0.9
    local k = self.dragging and KNOB + 3 or KNOB
    local knob = NW_Style.tex(NW.ICONS .. "Knob.png")
    if knob then
        self:drawTextureScaled(knob, kx - k / 2 - 1, cy - k / 2 - 1, k + 2, k + 2, 1, 0.08, 0.08, 0.09)
        self:drawTextureScaled(knob, kx - k / 2, cy - k / 2, k, k, a,
            NW_Style.accent.r, NW_Style.accent.g, NW_Style.accent.b)
    else
        self:drawRect(kx - k / 2, cy - k / 2, k, k, a,
            NW_Style.accent.r, NW_Style.accent.g, NW_Style.accent.b)
    end

    if self:preview() <= 0 then return end
    local px = self.width - self:preview()
    if self.mode == "stroke" then
        -- The stroke itself, at the width being chosen, in the ink being used:
        -- you pick a width by seeing the brush, not by reading a number.
        local ink = self.previewInk or { r = 0.9, g = 0.9, b = 0.9 }
        self:drawLine(nil, px + 3, cy, self.width - 3, cy, self.value, 1, ink.r, ink.g, ink.b)
    else
        local txt = self.suffix and (string.format("%.0f", self.value) .. self.suffix)
            or string.format("%.2f", self.value)
        self:drawText(txt, px + 4, cy - self.fontHalf,
            NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, UIFont.Small)
    end
end

function NW_Slider:new(x, y, width, height, target, onChange)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.moveWithMouse = false
    o.minValue = 1
    o.maxValue = 10
    o.step = 0.5
    o.value = 3
    o.target = target
    o.onChange = onChange
    o.dragging = false
    o.previewW = 54
    o.previewInk = nil
    o.mode = "stroke"   -- "stroke" draws the brush, anything else prints the value
    o.suffix = nil
    o.fontHalf = math.floor(getTextManager():getFontHeight(UIFont.Small) / 2)
    return o
end
