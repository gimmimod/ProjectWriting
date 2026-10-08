--[[ ============================================================================
    NW_NoteEntry - the note is written where the note goes.

    No dialog, no frame, no buttons: an invisible field sitting exactly where the
    text will end up, in the handwriting font and the ink colour in hand. It
    opens showing "Add note" as a hint; the first keystroke replaces it, so what
    you see while typing IS the note. Enter keeps it, Escape drops it.

    The field is the preview, which is why vanilla's own preview is switched off
    in NW_Map: that one reads fields off ISTextBoxMap and had nothing to read.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
require "NeatWriting/NW_Style"
require "NeatWriting/NW_Config"

NW_NoteEntry = ISPanel:derive("NW_NoteEntry")

function NW_NoteEntry:createChildren()
    self.entry = ISTextEntryBox:new(self.initial or "", 0, 0, self.width, self.height)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry:setMaxTextLength(45)
    self.entry:setFont(self.font or UIFont.Handwritten)
    self.entry.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.entry.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    local ink = self.ink or { r = 0.1, g = 0.1, b = 0.1 }
    self.entry:setTextRGBA(ink.r, ink.g, ink.b, 1)
    self.entry.onCommandEntered = function() self:accept() end
    -- La rotella sul campo e' la rotella sul biglietto: il campo lo copre tutto,
    -- e senza questo la riceverebbe lui e la butterebbe.
    self.entry.onMouseWheel = function(_, del) return self:onMouseWheel(del) end
    self:addChild(self.entry)
    self.entry:focus()
end

function NW_NoteEntry:noteText()
    return self.entry and self.entry:getText() or ""
end

function NW_NoteEntry:accept()
    local text = self:noteText()
    -- Anche vuoto vale, quando si stava correggendo: svuotare un biglietto e'
    -- il modo naturale di buttarlo via.
    if self.onAccept and (text ~= "" or self.initial) then
        self.onAccept(text, self.scale, self.angle)
    end
    self:done()
end

function NW_NoteEntry:cancel()
    if self.onCancel then self.onCancel() end
    self:done()
end

function NW_NoteEntry:done()
    if self.entry then self.entry:unfocus() end
    self:setVisible(false)
    self:removeFromUIManager()
    if NW_NoteEntry.instance == self then NW_NoteEntry.instance = nil end
end

--- Con Ctrl o Shift la rotella e' del biglietto: la si tiene, cosi' non passa a
--- chi sta sotto. Misura e angolo li cambia l'evento OnMouseWheel (NW_Placing),
--- ovunque sia il puntatore: qui ci si limita a non lasciarla scappare.
function NW_NoteEntry:onMouseWheel(del)
    local P = rawget(_G, "NW_Placing")
    return P ~= nil and P.gesture() ~= nil
end

function NW_NoteEntry:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then self:cancel() end
end

--- A click anywhere else means "that is the note": keep it rather than losing
--- what was typed.
---
--- ANYWHERE ELSE MEANS ELSE. The engine calls this on the parent even when the
--- click landed on one of its own children, so without the guard clicking into
--- the text box to move the caret would accept the note and close the editor -
--- the one place where you are most likely to click. The line is vanilla's own:
--- eight of its panels open this handler with it. (lesson 55)
function NW_NoteEntry:onMouseDownOutside(x, y)
    if self:isMouseOver() then return true end
    self:accept()
    return true
end

function NW_NoteEntry:prerender()
    -- No panel behind it. The only mark on screen is the text itself, plus a
    -- thin caret rule so it is clear where the writing is going.
    self:drawRect(0, self.height - 1, self.width, 1, 0.35,
        NW_Style.accent.r, NW_Style.accent.g, NW_Style.accent.b)
end

function NW_NoteEntry:render()
    if self:noteText() == "" then
        local ink = self.ink or NW_Style.dim
        self:drawText(getText("IGUI_Map_AddNote"), 2, 0, ink.r, ink.g, ink.b, 0.45,
            self.font or UIFont.Handwritten)
    end
    -- A che punto sono misura e angolo, sotto la riga: il campo resta dritto
    -- e della sua misura mentre si scrive, e il biglietto nasce come dice qui.
    local P = rawget(_G, "NW_Placing")
    if P and P.enabled() then
        local a = NW_Style.accent
        self:drawText(P.status(self.scale, self.angle), 2, self.height + 1, a.r, a.g, a.b, 0.9, UIFont.Small)
    end
end

function NW_NoteEntry:new(x, y, width, font, ink, onAccept, onCancel)
    local h = getTextManager():getFontHeight(font or UIFont.Handwritten) + 4
    local o = ISPanel.new(self, x, y, width, h)
    o.background = false
    o.moveWithMouse = false
    o.font = font
    o.ink = ink
    o.onAccept = onAccept
    o.onCancel = onCancel
    -- La misura di partenza e' quella dell'ultimo biglietto: e' quella con cui
    -- nascerebbe comunque (NW_Ink.dressMark).
    o.scale = NW and NW.lastSize and NW.lastSize("map", "note") or 1
    o.angle = 0
    return o
end

--- `initial` riapre l'editor su un biglietto gia' scritto, per correggerlo:
--- e' la funzione Modifica applicata a un riquadro di testo, che di un
--- ridimensionamento non saprebbe cosa farsene.
function NW_NoteEntry.open(x, y, width, font, ink, onAccept, onCancel, initial)
    if NW_NoteEntry.instance then NW_NoteEntry.instance:done() end
    local e = NW_NoteEntry:new(x, y, width, font, ink, onAccept, onCancel)
    e.initial = initial
    e:initialise()
    e:instantiate()
    e:addToUIManager()
    e:setAlwaysOnTop(true)
    NW_NoteEntry.instance = e
    return e
end
