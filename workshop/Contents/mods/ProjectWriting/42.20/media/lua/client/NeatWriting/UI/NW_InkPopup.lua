--[[ ============================================================================
    NW_InkPopup - the colour chooser for a multi-colour item.

    A pen that lays down five colours needs the colour to be picked, not cycled:
    clicking four times to get back to red is not a choice, it is a punishment.
    So the tile opens this, right beside itself, and the colour is one click.

    E LO STESSO SELETTORE GIRA LA MATITA. Una scelta puo' essere un id di
    inchiostro, e allora si disegna un campione di colore, oppure una tabella
    { id, icon, label }, e allora si disegna la casella con l'icona: la punta
    che scrive e il fondo che cancella. Un selettore solo per le due domande
    "con cosa scrivo", perche' da fuori sono la stessa domanda.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "NeatWriting/NW_Style"
require "NeatWriting/UI/NW_Tooltip"

NW_InkPopup = ISPanel:derive("NW_InkPopup")

-- Ventotto e non piu' ventidue: da quando un colore e' uno slot pieno, con il
-- suo bordo sfumato, a ventidue pixel il colore restava una macchia al centro.
local SWATCH = 28
local GAP = 4
local PAD = 5

--- Le misure di progetto per la scala del pannello che lo apre: una tavolozza
--- disegnata a 22 pixel accanto a un pannello tirato al doppio sembrerebbe di
--- un altra mod.
local function sized(scale, base)
    local s = scale or 1
    return math.max(10, math.floor((base or SWATCH) * s + 0.5)),
           math.max(2, math.floor(GAP * s + 0.5)),
           math.max(2, math.floor(PAD * s + 0.5))
end

function NW_InkPopup:createChildren()
    local sw, gap, pad = sized(self.nwScale, self.base)
    self.buttons = {}
    for i, id in ipairs(self.inks) do
        local b = ISButton:new(pad + (i - 1) * (sw + gap), pad, sw, sw,
            "", self, NW_InkPopup.onPick)
        b:initialise()
        b:instantiate()
        b:setDisplayBackground(false)
        b.internal = type(id) == "table" and id.id or id
        b.render = function() end
        local label = type(id) == "table" and id.label or NW.inkById(id).label
        NW_Tooltip.attach(b, getText(label))
        self:addChild(b)
        self.buttons[i] = b
    end
end

function NW_InkPopup:onPick(button)
    if self.onChosen then self.onChosen(button.internal) end
    self:close()
end

function NW_InkPopup:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if NW_InkPopup.instance == self then NW_InkPopup.instance = nil end
end

function NW_InkPopup:prerender()
    -- drawGroup, non drawBody: quel nome non e' mai esistito in NW_Style, e
    -- chiamare un campo nullo in Kahlua e' un'eccezione Java che il render non
    -- ferma. Il selettore c'era e riceveva i clic, ma non si disegnava: da fuori
    -- sembrava che la penna multicolore non aprisse niente. (lezione 38)
    NW_Style.drawGroup(self, 0, 0, self.width, self.height, 0.98)
end

function NW_InkPopup:render()
    local sw = sized(self.nwScale, self.base)
    -- LE STESSE CASELLE DELLA FILA DEGLI STRUMENTI (NW_Style.drawSlot): un
    -- colore e' lo slot riempito di quell'inchiostro, come la penna da cui si
    -- apre. Due disegni per la stessa cosa a due centimetri di distanza si
    -- leggerebbero come due cose.
    for i, btn in ipairs(self.buttons) do
        local choice = self.inks[i]
        if type(choice) == "table" then
            local on = choice.id == self.current
            NW_Style.drawSlot(self, btn:getX(), btn:getY(), sw, sw,
                { selected = on, hover = btn:isMouseOver(), fills = choice.fill and { choice.fill } or nil })
            local tex = NW_Style.tex(NW.ICONS .. choice.icon)
            if tex then
                local pad = math.max(2, math.floor(sw * 0.16))
                self:drawTextureScaled(tex, btn:getX() + pad, btn:getY() + pad,
                    sw - pad * 2, sw - pad * 2, 1,
                    NW_Style.text.r, NW_Style.text.g, NW_Style.text.b)
            end
        else
            local ink = NW.inkById(choice)
            NW_Style.drawSlot(self, btn:getX(), btn:getY(), sw, sw,
                { selected = choice == self.current, hover = btn:isMouseOver(),
                  fills = { ink.slot or ink } })
        end
    end
end

--- Any click outside closes it: a chooser you have to dismiss on purpose is a
--- dialog, and this is not meant to be one.
---
--- OUTSIDE HAS TO BE CHECKED. The engine calls this on the parent even when the
--- click landed on one of its children, and closing means leaving the UI
--- manager - while ISButton fires onclick on mouse UP. Vanish on the press and
--- the release has no button left to reach: the swatch lights up, the chooser
--- disappears, and the colour never changes. Eight vanilla panels open this
--- handler with exactly this line, one of them commented "clicked in a child".
---
--- This chooser has worked for months WITHOUT the guard, which is luck in the
--- frame ordering and not a licence to leave it out - the sharing panel, built
--- the same way, failed outright. (lesson 55)
function NW_InkPopup:onMouseDownOutside(x, y)
    if self:isMouseOver() then return true end
    self:close()
    return true
end

function NW_InkPopup:onMouseDown(x, y) return true end
function NW_InkPopup:onMouseUp(x, y) return true end

--- Quanto e' grande una casella con un'icona: un campione di colore si legge
--- a ventidue pixel, il disegno di una matita no.
local ICON_TILE = 34

function NW_InkPopup:new(x, y, inks, current, onChosen, scale)
    local base = type(inks[1]) == "table" and ICON_TILE or SWATCH
    local sw, gap, pad = sized(scale, base)
    local w = pad * 2 + #inks * sw + (#inks - 1) * gap
    local o = ISPanel.new(self, x, y, w, pad * 2 + sw)
    o.nwScale = scale or 1
    o.base = base
    o.background = false
    o.inks = inks
    o.current = current
    o.onChosen = onChosen
    return o
end

--- Opens one, replacing whatever was open. Screen coordinates.
function NW_InkPopup.open(x, y, inks, current, onChosen, scale)
    if NW_InkPopup.instance then NW_InkPopup.instance:close() end
    local p = NW_InkPopup:new(x, y, inks, current, onChosen, scale)
    p:initialise()
    p:instantiate()
    p:addToUIManager()
    -- SOPRA TUTTO, e non e' un vezzo. Il selettore e' un elemento di primo
    -- livello, mentre chi lo apre - la finestra di scrittura, l'ospite della
    -- mappa - e' setAlwaysOnTop(true). Senza questa riga nasceva sotto di
    -- loro: invisibile e non cliccabile. Da fuori sembrava che la penna
    -- multicolore non aprisse niente, e anche dopo aver corretto il disegno
    -- continuava a sembrarlo. Il tooltip e il campo dei biglietti fanno la
    -- stessa cosa per la stessa ragione.
    p:setAlwaysOnTop(true)
    -- Keep it on screen when the tile sits near the right edge.
    if p:getX() + p:getWidth() > getCore():getScreenWidth() then
        p:setX(getCore():getScreenWidth() - p:getWidth() - 4)
    end
    NW_InkPopup.instance = p
    return p
end
