--[[ ============================================================================
    NW_Tooltip - the mod's own hover label.

    The engine's tooltip is a square grey box with its own font: dropped in the
    middle of a Neat panel it reads as coming from somewhere else. This is the
    same pastille Hairstyler uses for style names (IHM_NeatTooltip), rebuilt on
    our surfaces so the two mods look like one interface.

    One shared panel, not one per button: a symbol sheet can hold two hundred
    tiles and only ever one of them is under the pointer.

    Lifetime is a lease rather than a pairing. attach() re-asserts show() on
    every frame its element is hovered, and the panel retires itself once nobody
    has renewed for a couple of frames. That is what keeps a label from
    outliving the thing it belongs to: switching tab in the sheet tears down
    every tile mid-hover, so there is no hide() call left to make.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "NeatWriting/NW_Style"

NW_Tooltip = NW_Tooltip or {}

local FONT  = UIFont.Small
local PAD_X = 9
local PAD_Y = 5
local GAP   = 8      -- distance from the element's edge
local LEASE = 2      -- frames a show() is good for

local Panel = ISPanel:derive("NW_TooltipPanel")

function Panel:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.text = ""
    o.lease = 0
    return o
end

--- UN'ETICHETTA NON E' UN COMANDO, e non deve prendersi il mouse.
---
--- Questo pannello sta nel gestore dell'interfaccia ed e' `setAlwaysOnTop`:
--- senza questa riga qualunque clic che cada dentro il suo rettangolo va a lui
--- invece che a quello che c'e' sotto. Non e' teoria - e' il difetto per cui il
--- selettore dei colori si apriva e non selezionava niente: il tooltip si mostra
--- SOTTO l'elemento che lo ha chiesto, la tavolozza si apre SOTTO lo stesso
--- slot, quindi l'etichetta della penna finiva esattamente sopra i campioni e
--- il clic andava a lei. Il selettore si vedeva, rispondeva al passaggio del
--- mouse, e non sceglieva mai un colore.
---
--- La riga e' quella di `ISToolTip:instantiate` - il tooltip di vanilla fa
--- esattamente questo, ed e' il motivo per cui a lui non succede.
function Panel:instantiate()
    ISPanel.instantiate(self)
    pcall(function() self.javaObject:setConsumeMouseEvents(false) end)
end

function Panel:prerender()
    -- Nobody renewed: the element is gone, or the pointer left it.
    self.lease = self.lease - 1
    if self.lease <= 0 then
        NW_Tooltip.hide()
        return
    end

    NW_Style.drawGroup(self, 0, 0, self.width, self.height, 1.0)

    local fh = getTextManager():getFontHeight(FONT)
    self:drawTextCentre(self.text, math.floor(self.width / 2),
        math.floor((self.height - fh) / 2),
        NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, FONT)
end

function Panel:render() end

local _panel = nil

--[[ absX/absY/w/h describe the hovered element in screen space.

    The label is centred under it and flips above near the bottom edge, then is
    clamped horizontally - a tile in the last column would otherwise push half
    the name off screen.
]]
function NW_Tooltip.show(text, absX, absY, w, h)
    text = tostring(text or "")
    if text == "" then return NW_Tooltip.hide() end

    local tm = getTextManager()
    local fh = tm:getFontHeight(FONT)
    local tw = tm:MeasureStringX(FONT, text) + PAD_X * 2
    local th = fh + PAD_Y * 2

    if not _panel then
        _panel = Panel:new(0, 0, tw, th)
        _panel:initialise()
        _panel:instantiate()
    end

    _panel.text  = text
    _panel.lease = LEASE
    _panel:setWidth(tw)
    _panel:setHeight(th)

    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()

    local x = absX + math.floor((w - tw) / 2)
    if x < 2 then x = 2 end
    if x + tw > sw - 2 then x = sw - 2 - tw end

    local y = absY + h + GAP
    if y + th > sh - 2 then y = absY - th - GAP end
    if y < 2 then y = 2 end

    _panel:setX(x)
    _panel:setY(y)

    if not _panel:getIsVisible() then
        _panel:setVisible(true)
        _panel:addToUIManager()
    end
    _panel:setAlwaysOnTop(true)
    _panel:bringToTop()
end

function NW_Tooltip.hide()
    if not _panel then return end
    _panel.lease = 0
    if _panel:getIsVisible() then
        _panel:setVisible(false)
        _panel:removeFromUIManager()
    end
end

--- Gives an element a Neat label instead of the engine's.
---
--- `text` may be a string or a function returning one, so a tile whose meaning
--- changes with the sheet does not need re-attaching.
function NW_Tooltip.attach(el, text)
    if not el or not text then return end

    -- Away with the vanilla one, or both show at once. NI_SquareButton reads
    -- tabName as its label, so that goes too.
    el.tooltip = nil
    el.tabName = nil
    if el.setTooltip then el:setTooltip(nil) end

    local previous = el.prerender
    el.prerender = function(self, ...)
        if previous then previous(self, ...) end
        if self:isMouseOver() then
            local t = text
            if type(t) == "function" then t = t(self) end
            NW_Tooltip.show(t, self:getAbsoluteX(), self:getAbsoluteY(),
                self:getWidth(), self:getHeight())
            self.nwTipShown = true
        elseif self.nwTipShown then
            self.nwTipShown = false
            NW_Tooltip.hide()
        end
    end
end

return NW_Tooltip
