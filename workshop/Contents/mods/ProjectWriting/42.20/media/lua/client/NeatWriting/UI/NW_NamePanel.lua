--[[ ============================================================================
    NW_NamePanel - come si chiama la cosa che stai per fare.

    Un pannello Neat piccolo, al centro dello schermo: intestazione con l'icona
    di quello che si sta fabbricando, un campo gia' riempito con il nome buono
    per la maggior parte delle volte, e una spunta verde che conferma. Invio
    conferma anche lui, Esc lascia perdere.

    PERCHE' UN PANNELLO E NON UN CAMPO NUDO. Il primo tentativo riusava
    NW_NoteEntry - il campo che si usa per i biglietti sulla mappa - appoggiato
    sopra il velo di inquadratura. Funzionava, e sbagliava due cose: un campo
    senza cornice in mezzo a una mappa non si distingue da un'annotazione che si
    sta scrivendo sulla mappa stessa, ed e' esattamente il gesto di fianco; e
    non c'era niente da premere per dire "si'", quindi l'unico modo di
    confermare era premere Invio e sperare. Il nome di un oggetto che restera'
    in giro per la partita merita una finestra che dica cosa sta per succedere.

    IL CAMPO E' QUELLO DI VANILLA, SVESTITO. `ISTextEntryBox` disegna un
    rettangolo grigio con un bordo squadrato; gli si mette fondo e bordo
    trasparenti e si sostituisce il suo `prerender` con `NW_Style.drawTextField`.
    Cosi' restano il cursore, la selezione e la gestione dei tasti - tutta la
    parte che vale - e se ne va solo quella che stona. E' la ricetta
    dell'armadio di Equipment (NEQ_Wardrobe:onRename), copiata e non inventata.

    IL NOME DI PARTENZA E' GIA' SCRITTO E GIA' SELEZIONATO in senso pratico:
    chi va di fretta preme Invio e ha finito, chi vuole cambiarlo cancella. Un
    campo vuoto con un suggerimento in grigio costringe tutti a scrivere.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Style"

NW_NamePanel = ISPanel:derive("NW_NamePanel")

NW_NamePanel.instance = nil

local WIDTH = 320
local MAX_CHARS = 40

-- ---------------------------------------------------------------------------
-- Costruzione
-- ---------------------------------------------------------------------------

function NW_NamePanel:createChildren()
    local m = self.m

    local entry = ISTextEntryBox:new(self.initial or "", 0, 0, 10, 10)
    entry:initialise()
    entry:instantiate()
    pcall(function() entry:setMaxTextLength(MAX_CHARS) end)
    entry.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    entry.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    entry.prerender = function(box)
        NW_Style.drawTextField(box, 0, 0, box.width, box.height)
    end
    entry.onCommandEntered = function() self:confirm() end
    self.entry = entry
    self:addChild(entry)

    -- La spunta e' verde fissa, non si accende al passaggio: e' l'azione
    -- affermativa della finestra, e in famiglia quelle si riconoscono dal
    -- colore prima che dal disegno.
    self.okBtn = NW_Style.newSquareButton(0, 0, m.btn, NW_Style.tex(NW.ICONS .. "Icon_True.png"),
        self, NW_NamePanel.confirm, NW_Style.selection)
    self:addChild(self.okBtn)

    self:layout()
    entry:focus()
end

function NW_NamePanel:layout()
    local m = self.m
    local y = m.headerH + m.pad
    local right = self.width - m.pad

    self.okBtn:setWidth(m.btn)
    self.okBtn:setHeight(m.btn)
    self.okBtn:setX(right - m.btn)
    self.okBtn:setY(y + math.floor((m.fieldH - m.btn) / 2))

    self.entry:setX(m.pad)
    self.entry:setY(y)
    self.entry:setWidth(right - m.btn - m.gap - m.pad)
    self.entry:setHeight(m.fieldH)

    self:setHeight(y + m.fieldH + m.pad)
end

-- ---------------------------------------------------------------------------
-- Le due uscite
-- ---------------------------------------------------------------------------

function NW_NamePanel:confirm()
    local name
    pcall(function() name = self.entry:getInternalText() end)
    if not name or name == "" then name = self.initial end
    local done = self.onDone
    self:close("confermato")
    if done then done(name) end
end

function NW_NamePanel:cancel()
    local gone = self.onCancel
    self:close("annullato")
    if gone then gone() end
end

function NW_NamePanel:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then self:cancel() end
end

--- Un clic fuori NON chiude. Questo non e' un selettore da cui si scivola via:
--- e' una domanda con due risposte, e chiuderlo per sbaglio buttando via il
--- lavoro appena fatto - il rettangolo inquadrato - sarebbe la cosa peggiore
--- che possa fare. Si esce dalla spunta o da Esc, apposta.
function NW_NamePanel:onMouseDown(x, y) return true end
function NW_NamePanel:onMouseUp(x, y) return true end

function NW_NamePanel:close(why)
    if NW_NetClient and NW_NetClient.verbose then
        print("NW_NamePanel: " .. tostring(why))
    end
    if self.entry then pcall(function() self.entry:unfocus() end) end
    self:setVisible(false)
    self:removeFromUIManager()
    if NW_NamePanel.instance == self then NW_NamePanel.instance = nil end
end

-- ---------------------------------------------------------------------------
-- Disegno
-- ---------------------------------------------------------------------------

function NW_NamePanel:prerender()
    NW_Style.drawWindow(self, 0, 0, self.width, self.height, self.m.headerH)
end

function NW_NamePanel:render()
    local m = self.m
    NW_Style.drawHeaderLabel(self, m.headerH,
        self.icon and NW_Style.tex(NW.ICONS .. self.icon) or nil,
        self.title, m.titleFont, m.titleH)
end

-- ---------------------------------------------------------------------------
-- Aprire
-- ---------------------------------------------------------------------------

--- Chiede un nome, al centro dello schermo.
---
---     NW_NamePanel.open{
---         title   = getText("IGUI_NW_MapMake"),
---         icon    = "CreateMapNote.png",
---         initial = "Mappa annotata di Gimmi",
---         scale   = 1.5,
---         onDone  = function(name) end,
---         onCancel = function() end,
---     }
function NW_NamePanel.open(opts)
    if NW_NamePanel.instance then NW_NamePanel.instance:close("richiamato") end
    opts = opts or {}

    local s = opts.scale or 1
    local w = math.floor(WIDTH * s)
    local p = NW_NamePanel:new(0, 0, w, 100, s)
    p.title = opts.title
    p.icon = opts.icon
    p.initial = opts.initial or ""
    p.onDone = opts.onDone
    p.onCancel = opts.onCancel
    p:initialise()
    p:instantiate()

    -- Al centro, e solo dopo che `layout` ha detto quanto e' alto davvero.
    p:setX(math.floor((getCore():getScreenWidth() - p:getWidth()) / 2))
    p:setY(math.floor((getCore():getScreenHeight() - p:getHeight()) / 2))
    p:addToUIManager()
    -- Sopra la mappa e sopra il velo di inquadratura, che sono tutti e due
    -- setAlwaysOnTop: senza, nascerebbe dietro e non lo troverebbe nessuno.
    p:setAlwaysOnTop(true)
    NW_NamePanel.instance = p
    return p
end

function NW_NamePanel:new(x, y, width, height, scale)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.moveWithMouse = false

    local s = scale or 1
    local m = {}
    m.headerH = math.floor(22 * s)
    m.pad     = math.max(6, math.floor(10 * s))
    m.gap     = math.max(4, math.floor(6 * s))
    m.fieldH  = math.floor(24 * s)
    m.btn     = m.fieldH
    m.titleFont, m.titleH = NW_Style.pickFont(m.headerH - math.floor(6 * s))
    o.m = m
    return o
end

return NW_NamePanel
