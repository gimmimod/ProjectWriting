--[[ ============================================================================
    NW_Panel - the Writing panel.

    One panel for the whole mod. It is handed a "surface" descriptor and builds
    itself from that, so the map and a diary page get the same panel with the
    same habits. What differs between them is two answers, not two panels: the
    map has no Word tool because linear text needs a ruled surface to flow on,
    and only a sheet of paper can be given a name.

        surface = {
            word      = false,      -- show the linear-text tool
            rotate    = true,       -- show the Rotate action
            canRename = false,      -- show the rename pencil by the subject
            title     = "Map",      -- what is being written on
            getPlayer = function() end,   -- asked for, never cached
            onTool    = function(id) end,
            onInk     = function(id, erasing) end,
            onWidth   = function(n) end,
            onSymbol  = function(sym) end,
            onRename  = function(name) end,
            onClose   = function() end,
        }

    Anything a surface leaves out keeps the map's answer, which is why NW_Map
    never had to be touched to add either of the two new ones.

    The tool strip shows the real items out of the inventory - your pen, your
    pencil, your eraser, each with its own icon - not abstract colour chips.

    LAYOUT. Sections are laid out top to bottom by :layout(), each recording the
    box it occupies; the panel ends up exactly as tall as the visible sections.
    Nothing is positioned by eye. Anatomy is the family's
    (METODO/01_STILE_NEATUI): MainTitle_BG header over MainPanelBG_FlatTop body,
    InnerPanel_BG for the group boxes, orange only on active states.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Net"
require "NeatWriting/NW_Style"
require "NeatWriting/NW_Tools"
require "NeatWriting/UI/NW_Slider"
require "NeatWriting/UI/NW_InkPopup"
require "NeatWriting/UI/NW_SymbolPicker"
require "NeatWriting/NW_Share"
require "NeatWriting/UI/NW_SharePanel"
require "NeatWriting/UI/NW_Framer"
require "NeatWriting/NW_Cartography"
require "NeatWriting/NW_Sound"
require "NeatWriting/UI/NW_Tooltip"

NW_Panel = ISPanel:derive("NW_Panel")

local FONT_SMALL  = getTextManager():getFontHeight(UIFont.Small)
local FONT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

local RESCAN_MS = 500

-- Quanti pixel di trascinamento in verticale valgono un punto di scala: da 1 a
-- 2 sono trecento pixel, cioe' il gesto di un polso e non di un braccio.
local SCALE_DRAG_PX = 300

-- Le misure di progetto, quelle a scala 1. Da qui in poi nel file non si
-- scrive piu' un numero: si legge self.metrics, che e' questa tabella
-- moltiplicata per quanto il giocatore ha tirato la maniglia.
local BASE = {
    pad     = NW.PAD,   -- margine del pannello
    gap     = 8,        -- fra una sezione e l'altra
    box     = 7,        -- aria dentro un riquadro
    slot    = 40,       -- la casella di uno strumento
    slotGap = 6,
    toolBtn = 34,       -- il tasto di uno strumento
    btnGap  = 14,       -- passo fra i tasti di una riga
}

-- ---------------------------------------------------------------------------
-- La misura
-- ---------------------------------------------------------------------------
--
-- Tutto deriva da un numero solo, la scala, e la scala la decide la maniglia
-- d'angolo - come la barra di XP Drop, che e' dove questa ricetta e' gia'
-- stata provata. A 4K un pannello disegnato a 360 pixel e' un francobollo, e
-- ingrandire il gioco intero non e' una risposta: si ingrandisce questo.
--
-- I caratteri salgono con il resto (NW_Style.pickFont), altrimenti un pannello
-- al doppio resta con le stesse letterine in mezzo al vuoto.

local function round(v) return math.floor(v + 0.5) end

--- Vero per uno strumento che scrive E cancella: la matita, con la gommetta
--- dietro. NW.ERASER.types include gia' `Pencil` per questo motivo.
---
--- Non e' un caso speciale inventato: e' una matita, e girarla e' quello che si
--- fa con una matita. Una penna non ha il rovescio, una gomma non ha la punta.
---
--- STA QUI IN CIMA perche' la usa anche `createChildren`, che sta molto piu'
--- su: una locale dichiarata dopo chi la chiama non e' quella locale, e' una
--- globale mai assegnata - cioe' nil. (lezione 18)
local function hasRubberEnd(tool)
    return tool and tool.isEraser and #tool.inks > 0
end

function NW_Panel:computeMetrics()
    local s = self.nwScale
    local m = {}
    for name, v in pairs(BASE) do m[name] = math.max(1, round(v * s)) end

    m.font,    m.fontH    = NW_Style.pickFont(FONT_SMALL * s)
    m.fontBig, m.fontBigH = NW_Style.pickFont(FONT_MEDIUM * s)
    -- La maniglia NON scala. Sedici pixel fissi, come NR_ResizeWidget di
    -- Rocco e come la barra di XP Drop: su un pannello tirato al doppio una
    -- maniglia doppia diventa un pulsante, e smette di essere il segno
    -- discreto d'angolo che la famiglia usa dappertutto.
    m.grip = 16

    m.headerH = math.floor(m.fontBigH * 1.5)
    m.rowH    = m.fontH + round(6 * s)
    m.sliderH = m.fontH + round(10 * s)

    self.metrics = m
end

--- Il tetto vero: meta' schermo.
---
--- NW.SCALE.MAX e' un numero, questo e' una misura. Il pannello e' il bordo di
--- quello che si sta guardando - una pagina, una mappa - e un bordo che si
--- prende piu' di meta' dello schermo ha smesso di essere un bordo. Su un
--- monitor stretto e' anche l'unica cosa che tiene la maniglia raggiungibile:
--- un comando che si puo' usare per andare in un verso solo e' una trappola
--- (la stessa lezione della finestra di lettura).
function NW_Panel:maxScale()
    local room = getCore():getScreenWidth() * 0.5
    return math.max(NW.SCALE.MIN, math.min(NW.SCALE.MAX, room / NW.PANEL_MIN_W))
end

--- La larghezza per la scala e il fattore di larghezza di adesso. La conta sta
--- in NW.panelWidth perche' serve identica a chi deve lasciare posto al
--- pannello prima che esista (la pagina, la mappa di carta).
function NW_Panel:targetWidth()
    return NW.panelWidth(self.baseWidth, self.nwScale, self.widthF)
end

--- La larghezza nuova. Stessa regola di setScale: `live` mentre la maniglia e'
--- in mano, e allora la tavola dei simboli si lascia stare fino a che non la si
--- molla - rifarla vuol dire ridisporre centoquaranta caselle.
function NW_Panel:setWidthFactor(f, live)
    f = math.max(0.5, math.min(NW.SCALE.MAX, f or 1))
    if live and math.abs(f - (self.widthF or 1)) < 0.0005 then return end
    self.widthF = f
    self:setWidth(self:targetWidth())
    self:resizeChildren()
    if not live then
        if self.symbolPicker then self.symbolPicker:build() end
        NW.setPanelWidthFactor(f)
    end
    self:layout()
end

--- La misura nuova. `live` mentre la maniglia e' ancora in mano: allora si
--- rifa' solo quello che costa poco, e la tavola dei simboli - centoquaranta
--- caselle - si lascia stare fino a che la maniglia non si molla.
function NW_Panel:setScale(s, live)
    s = math.max(NW.SCALE.MIN, math.min(s or 1, self:maxScale()))
    -- Mentre si trascina si lascia perdere il fotogramma che non cambia
    -- niente. Alla fine no: li' la misura e' gia' quella giusta - l'ha messa
    -- il trascinamento - e quello che manca e' proprio il resto, la tavola
    -- rifatta e il numero scritto sul disco.
    if live and math.abs(s - self.nwScale) < 0.0005 then return end
    self.nwScale = s
    self:computeMetrics()
    self:setWidth(self:targetWidth())
    self:resizeChildren()
    if not live then
        if self.symbolPicker then self.symbolPicker:setScale(s) end
        NW.setPanelScale(s)
    end
    self:layout()
end

--- Il tasto della condivisione ha senso solo in rete, e solo su una mappa: da
--- soli non c'e' nessuno con cui spartire, e su un foglio quello che si scrive
--- viaggia con l'oggetto - chi ce l'ha in mano lo legge, e non c'e' niente da
--- decidere. Le mappe sono le superfici senza lo strumento del testo a righe
--- (`word == false`), che e' la stessa cosa che distingue una mappa da una
--- pagina in tutto il resto del pannello.
function NW_Panel:showsShare()
    if not isClient() then return false end
    if not NW.sharing() then return false end
    if NW.vanillaMap() then return false end
    return self.surface.word == false
end

--- Il ritaglio si fa solo sulla mappa del mondo - una mappa di carta e' gia'
--- un ritaglio - e solo con di che scrivere e su cosa scrivere.
function NW_Panel:showsCrop()
    if NW.vanillaMap() then return false end
    if self.surface.word ~= false then return false end
    if not (self.surface.isWorld and self.surface.isWorld()) then return false end
    local p = self:player()
    return NW_Tools.canWrite(p) and NW_Tools.hasPaper(p)
end

--- Il travaso si offre solo aprendo una delle nostre mappe fabbricate: e'
--- l'unico caso in cui c'e' qualcosa da portare via, e chiederlo davanti alla
--- propria mappa del mondo non vorrebbe dire niente.
function NW_Panel:showsGrab()
    if not self.surface.getMapItem then return false end
    return NW_Cartography.isOurs(self.surface.getMapItem())
end

--- I tasti dell'header che esistono davvero, dalla X verso sinistra.
---
--- Si costruisce invece di scriverli in una tabella al volo: `ipairs` si ferma
--- al primo nil, e con il tasto della mappa assente - una pagina non ce l'ha -
--- quelli dopo sarebbero stati saltati senza dire niente.
function NW_Panel:headerButtons()
    local out = { self.closeBtn }
    -- La visibilita' si guarda anche qui, non solo l'esistenza: da quando il
    -- tasto della mappa si spegne davanti a una mappa nostra, contarlo comunque
    -- lascerebbe un buco nella fila al posto suo.
    if self.worldBtn and self.worldBtn:isVisible() then out[#out + 1] = self.worldBtn end
    if self.shareBtn and self.shareBtn:isVisible() then out[#out + 1] = self.shareBtn end
    if self.cropBtn and self.cropBtn:isVisible() then out[#out + 1] = self.cropBtn end
    if self.grabBtn and self.grabBtn:isVisible() then out[#out + 1] = self.grabBtn end
    -- Il tasto del banco c'e' sempre ma si vede solo se l'opzione e' accesa:
    -- se e' spento non prende posto nella fila, o l'header lascerebbe un buco.
    return out
end

--- I figli alla misura corrente.
---
--- Un tasto quadrato disegna la sua icona in proporzione alla propria
--- scatola - sia il nostro ripiego sia il widget del framework - quindi
--- cambiargli la scatola basta a cambiargli la faccia.
function NW_Panel:resizeChildren()
    local m = self.metrics
    local innerW = self.width - m.pad * 2

    local hb = NW_Style.headerButtonSize(m.headerH)
    for _, b in ipairs(self:headerButtons()) do
        b:setWidth(hb)
        b:setHeight(hb)
    end

    for _, b in pairs(self.toolButtons) do
        b:setWidth(m.toolBtn)
        b:setHeight(m.toolBtn)
    end
    if self.isoBtn then
        self.isoBtn:setWidth(m.toolBtn)
        self.isoBtn:setHeight(m.toolBtn)
    end
    self:placeButtonRow(self.toolOrder, self.toolButtons, innerW)
    self:placeButtonRow(self.actionOrder, self.actionButtons, innerW)

    for _, b in ipairs(self.slotButtons) do
        b:setWidth(m.slot)
        b:setHeight(m.slot)
    end

    if self.renameBtn then
        self.renameBtn:setWidth(m.rowH)
        self.renameBtn:setHeight(m.rowH)
    end

    self.widthSlider:setX(m.pad + m.box)
    self.widthSlider:setWidth(innerW - m.box * 2)
    self.widthSlider:setHeight(m.sliderH)
    self.widthSlider.nwScale = self.nwScale

    self.symbolPicker:setX(m.pad)
    self.symbolPicker:setWidth(innerW)
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

function NW_Panel:createChildren()
    -- La misura salvata puo' venire da uno schermo piu' largo di quello di
    -- adesso, o da un pannello di progetto piu' stretto: si rimette dentro i
    -- limiti prima di costruirci sopra qualunque cosa.
    self.nwScale = math.max(NW.SCALE.MIN, math.min(self.nwScale, self:maxScale()))
    self:setWidth(self:targetWidth())

    self:computeMetrics()
    local m = self.metrics
    local PAD, HEADER_H, BOX, ROW_H = m.pad, m.headerH, m.box, m.rowH
    local innerW = self.width - PAD * 2

    -- Red and always lit, like every close button in the family (NR_Header:265).
    local btn = NW_Style.headerButtonSize(HEADER_H)
    self.closeBtn = NW_Style.newSquareButton(0, 0, btn, NW_Style.iconClose(),
        self, NW_Panel.onClose, NW_Style.close)
    self:addChild(self.closeBtn)

    -- Il collegamento alla mappa del mondo, quando la superficie ce l'ha.
    --
    -- E' l'UNICA differenza fra il pannello di una mappa di carta e quello di un
    -- foglio: una mappa stampata sa dove sta nel mondo, e portare li' la vista
    -- e' una cosa che solo lei puo' fare. Tutto il resto - strumenti, penne,
    -- gomma, sposta, ruota - e' identico, ed e' identico perche' e' lo stesso
    -- pannello, non perche' due pannelli si somigliano.
    if self.surface.onWorldMap then
        -- La stessa icona che il pannello di lettura mette sui suoi tasti
        -- mappa: e' la stessa cosa - "portami li' sulla mappa" - e due disegni
        -- diversi per un gesto solo si leggono come due gesti diversi.
        self.worldBtn = NW_Style.newSquareButton(0, 0, btn,
            NW_Style.tex(NW.ICONS .. "WorldMap.png"), self, NW_Panel.onWorldMap)
        self:addChild(self.worldBtn)
        NW_Tooltip.attach(self.worldBtn, getText("IGUI_NW_RevealOnMap"))
    end

    -- Con chi stai scrivendo: l'aeroplanino di carta.
    --
    -- SOLO IN RETE E SOLO SULLA MAPPA: da soli non c'e' nessuno con cui
    -- spartire, e su un foglio quello che si scrive viaggia con l'oggetto -
    -- chi ce l'ha in mano lo legge, e non c'e' niente da decidere. Come il
    -- tasto del banco, si costruisce sempre e si nasconde: la mappa del mondo
    -- si costruisce una volta per partita, e un tasto creato "solo se serviva
    -- allora" non comparirebbe mai piu'.
    self.shareBtn = NW_Style.newSquareButton(0, 0, btn,
        NW_Style.tex(NW.ICONS .. "Share.png"), self, NW_Panel.onShare)
    self:addChild(self.shareBtn)
    self.shareBtn:setVisible(self:showsShare())
    NW_Tooltip.attach(self.shareBtn, function()
        return getText("IGUI_NW_ShareTip") .. ": " .. NW_Share.label(self:player())
    end)

    -- Ritagliare un pezzo di mappa e farne un foglio.
    --
    -- SOLO SULLA MAPPA DEL MONDO, e solo con un foglio e qualcosa per scrivere
    -- a portata di mano: e' una cosa che si fabbrica, e un tasto che si preme
    -- per sentirsi dire "non hai la carta" e' un tasto che mente. La condizione
    -- si guarda a ogni fotogramma perche' la carta si consuma e si raccoglie
    -- mentre la mappa e' aperta.
    self.cropBtn = NW_Style.newSquareButton(0, 0, btn,
        NW_Style.tex(NW.ICONS .. "CreateMapNote.png"), self, NW_Panel.onCrop)
    self:addChild(self.cropBtn)
    self.cropBtn:setVisible(self:showsCrop())
    NW_Tooltip.attach(self.cropBtn, getText("IGUI_NW_MapMake"))

    -- Portare sulla propria mappa i segni di una mappa trovata.
    self.grabBtn = NW_Style.newSquareButton(0, 0, btn,
        NW_Style.tex(NW.ICONS .. "WorldMap.png"), self, NW_Panel.onGrab)
    self:addChild(self.grabBtn)
    self.grabBtn:setVisible(self:showsGrab())
    NW_Tooltip.attach(self.grabBtn, getText("IGUI_NW_MapTake"))

    self.slotButtons = {}

    -- Function row, built from the surface: no Word tool without a page.
    self.toolButtons = {}
    self.toolOrder = {}
    for _, t in ipairs(NW.TOOLS) do
        if (not t.word) or self.surface.word then
            self.toolOrder[#self.toolOrder + 1] = t
        end
    end
    self:buildButtonRow(self.toolOrder, innerW, self.toolButtons)

    -- Actions are filtered the same way, for whoever needs it: the page turned
    -- out to need all three, once drawTextureAllPoint gave us a rotated quad.
    self.actionOrder = {}
    for _, a in ipairs(NW.ACTIONS) do
        if a.id ~= "rotate" or self.surface.rotate ~= false then
            self.actionOrder[#self.actionOrder + 1] = a
        end
    end
    -- LA PROSPETTIVA STA FRA LE FUNZIONI, in coda a sposta, ruota e
    -- ridimensiona: e' una cosa che si decide sui segni, non sul pannello, e
    -- nell'header stava fra i tasti della finestra. Solo sulla mappa del mondo,
    -- l'unica che si inclina. Le icone sono quelle del tasto della prospettiva
    -- in fondo alla mappa, perche' parlano della stessa cosa: acceso mostra la
    -- vista isometrica (i segni nascono stesi), spento quella dall'alto (dritti).
    --
    -- E' UN INTERRUTTORE, NON UNO STRUMENTO: acceso dice che i segni che si
    -- posano da adesso nascono stesi (NW_Ink.dressMark), e intanto in mano
    -- resta quello che c'era. Per questo non entra nello stato attivo comune.
    if self.surface.isWorld and self.surface.isWorld() then
        self.actionOrder[#self.actionOrder + 1] = {
            id = "iso", toggle = true, label = "IGUI_NW_MarksPerspective",
            tex = NW_Style.tex(NW.ICONS .. (NW.marksFollowPerspective()
                and "ViewIsometric.png" or "ViewTop.png")),
        }
    end
    self.actionButtons = {}
    self:buildButtonRow(self.actionOrder, innerW, self.actionButtons)
    self.isoBtn = self.actionButtons.iso
    -- Both rows share one active state: only ever one tool in hand.
    for id, b in pairs(self.actionButtons) do
        if id ~= "iso" then self.toolButtons[id] = b end
    end

    self.widthSlider = NW_Slider:new(PAD + BOX, 0, innerW - BOX * 2, m.sliderH, self, NW_Panel.onWidth)
    self.widthSlider.nwScale = self.nwScale
    self.widthSlider:initialise()
    self.widthSlider:instantiate()
    self.widthSlider.minValue = NW.BRUSH.MIN
    self.widthSlider.maxValue = NW.BRUSH.MAX
    self.widthSlider.step = 0.5
    self.widthSlider:setValue(NW.BRUSH.DEFAULT, true)
    self:addChild(self.widthSlider)
    self.widthSlider:setVisible(false)

    self.symbolPicker = NW_SymbolPicker:new(PAD, 0, innerW, function(sym)
        self.currentSymbol = sym
        if self.surface.onSymbol then self.surface.onSymbol(sym) end
    end)
    self.symbolPicker.nwScale = self.nwScale
    self.symbolPicker:initialise()
    self.symbolPicker:instantiate()
    self:addChild(self.symbolPicker)
    self.symbolPicker:setVisible(false)

    -- Renaming the sheet: a pencil where the name is, which turns into the tick
    -- that confirms while it is being typed. The same gesture as Equipment's
    -- wardrobe, so whoever has used that one finds it here.
    if self.surface.canRename then
        self.renameBtn = NW_Style.newSquareButton(0, 0, ROW_H,
            NW_Style.tex(NW.ICONS .. "Icon_Rename.png"), self, NW_Panel.onRename)
        NW_Tooltip.attach(self.renameBtn, function()
            return getText(self.renaming and "IGUI_NW_Confirm" or "IGUI_NW_Rename")
        end)
        self:addChild(self.renameBtn)
    end

    -- Un quaderno chiuso a chiave si legge e non si scrive. I tasti restano al
    -- loro posto, spenti: sparire vorrebbe dire un pannello di forma diversa
    -- per la stessa cosa, e chi lo apre non capirebbe cosa gli manca.
    if self.surface.readOnly then
        for _, b in pairs(self.toolButtons) do
            if b.setEnable then b:setEnable(false) end
        end
    end

    self:watchFreehand()
    self:layout()
end

-- ---------------------------------------------------------------------------
-- Rinominare
-- ---------------------------------------------------------------------------

function NW_Panel:onRename()
    if self.renaming then self:commitRename() return end

    self.renaming = true
    NW_Style.setButtonIcon(self.renameBtn, NW_Style.tex(NW.ICONS .. "Icon_True.png"))

    -- It is born with arbitrary measures: layout() is what puts it in place,
    -- because layout() is the only one that knows where the row ends.
    local entry = ISTextEntryBox:new(self.surface.title or "", 0, 0, 10, 10)
    entry:initialise()
    entry:instantiate()
    pcall(function() entry:setMaxTextLength(40) end)
    entry.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    entry.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    entry.prerender = function(box)
        NW_Style.drawTextField(box, 0, 0, box.width, box.height)
    end
    entry.onCommandEntered = function() self:commitRename() end
    self.renameEntry = entry
    self:addChild(entry)

    self:layout()
    entry:focus()
end

function NW_Panel:commitRename()
    local entry = self.renameEntry
    self.renaming = false
    self.renameEntry = nil
    if self.renameBtn then
        NW_Style.setButtonIcon(self.renameBtn, NW_Style.tex(NW.ICONS .. "Icon_Rename.png"))
    end
    if entry then
        local name = entry:getInternalText()
        if name and name ~= "" and self.surface.onRename then self.surface.onRename(name) end
        entry:unfocus()
        self:removeChild(entry)
    end
    self:layout()
end

--- A centred row of square buttons at a fixed pitch. Spreading them across the
--- full width scattered them into the corners and left holes in the middle
--- that meant nothing; a tight centred group reads as one control.
function NW_Panel:buildButtonRow(defs, innerW, into)
    local m = self.metrics
    for _, d in ipairs(defs) do
        local b = NW_Style.newSquareButton(0, 0, m.toolBtn,
            d.tex or NW_Style.tex(NW.ICONS .. d.icon), self,
            d.toggle and NW_Panel.onIso or NW_Panel.onTool)
        b.internal = d.id
        NW_Tooltip.attach(b, getText(d.label))
        self:addChild(b)
        into[d.id] = b
    end
    self:placeButtonRow(defs, into, innerW)
end

--- Dove cade ognuno, alla misura corrente. Separata dalla costruzione perche'
--- la maniglia la richiama a ogni pixel, e i tasti si costruiscono una volta.
function NW_Panel:placeButtonRow(defs, into, innerW)
    local m = self.metrics
    -- Solo i tasti accesi: uno spento (la penna, con il disegno a mano libera
    -- tolto dalla partita) non deve lasciare un buco in mezzo alla fila.
    local shown = {}
    for _, d in ipairs(defs) do
        local b = into[d.id]
        if b and b:isVisible() then shown[#shown + 1] = b end
    end
    local n = #shown
    local span = n * m.toolBtn + math.max(0, n - 1) * m.btnGap
    local x0 = m.pad + math.floor((innerW - span) / 2)
    for i, b in ipairs(shown) do
        b:setX(x0 + (i - 1) * (m.toolBtn + m.btnGap))
    end
end

--- Il disegno a mano libera si puo' spegnere dalle opzioni sandbox (NW_Net), e
--- un admin puo' farlo a partita avviata: il pannello se ne accorge da solo. La
--- penna sparisce dalla fila, e se era in mano si posa.
function NW_Panel:watchFreehand()
    local allowed = NW_Net.freehandAllowed()
    if allowed == self.nwFreehand then return end
    self.nwFreehand = allowed
    local draw = self.toolButtons and self.toolButtons.draw
    if draw then draw:setVisible(allowed) end
    if not allowed and self.currentTool == "draw" then
        self:setTool(nil)
        if self.surface.onTool then self.surface.onTool(nil) end
    end
    self:placeButtonRow(self.toolOrder, self.toolButtons, self.width - self.metrics.pad * 2)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

--- Walks the sections top to bottom, records each one's box, and sizes the
--- panel to what is visible. Every y in this panel comes from here.
function NW_Panel:layout()
    local m = self.metrics
    local PAD, GAP, BOX, HEADER_H, ROW_H = m.pad, m.gap, m.box, m.headerH, m.rowH
    local SLOT, SLOT_GAP, TOOL_BTN = m.slot, m.slotGap, m.toolBtn

    local y = HEADER_H + PAD

    self.subjectY = y
    self.titleLimit = self.width - PAD
    if self.renameBtn then
        self.renameBtn:setX(self.width - PAD - ROW_H)
        self.renameBtn:setY(y)
        self.titleLimit = self.renameBtn:getX() - GAP
    end
    if self.renameEntry then
        self.renameEntry:setX(PAD)
        self.renameEntry:setY(y)
        self.renameEntry:setWidth(math.max(24, self.titleLimit - PAD))
        self.renameEntry:setHeight(ROW_H)
    end
    y = y + ROW_H + GAP

    -- Group 1: what is in the bag.
    local count = math.max(1, #self.tools)
    local rows = math.max(1, math.ceil(count / self:slotsPerRow()))
    self.stripY = y + BOX
    local stripH = rows * SLOT + (rows - 1) * SLOT_GAP
    self.stripBox = { y = y, h = stripH + BOX * 2 }
    self:placeStrip()
    y = y + self.stripBox.h + GAP

    -- Group 2: what to do, and what to do to what is already there.
    local toolsY = y + BOX
    self.toolsY = toolsY
    for _, t in ipairs(self.toolOrder) do
        local b = self.toolButtons[t.id]
        if b then b:setY(toolsY) end
    end
    self.ruleY = toolsY + TOOL_BTN + math.floor(GAP / 2)
    local actionsY = self.ruleY + math.floor(GAP / 2) + 1
    self.actionsY = actionsY
    for _, b in pairs(self.actionButtons) do b:setY(actionsY) end
    self.actionBox = { y = y, h = (actionsY + TOOL_BTN + BOX) - y }
    y = y + self.actionBox.h + GAP

    -- Whatever the current tool brings with it.
    if self.widthSlider:isVisible() then
        self.widthSlider:setY(y + BOX)
        self.sliderBox = { y = y, h = self.widthSlider:getHeight() + BOX * 2 }
        y = y + self.sliderBox.h + GAP
    else
        self.sliderBox = nil
    end
    if self.symbolPicker:isVisible() then
        -- The panel grows to hold the sheet rather than the sheet scrolling
        -- inside a fixed window; it only starts scrolling when there is no
        -- screen left to grow into.
        local room = (self.maxHeight or 10000) - y - PAD - m.grip
        self.symbolPicker:fitInto(room)
        self.symbolPicker:setY(y)
        y = y + self.symbolPicker:getHeight() + GAP
    end

    -- In fondo resta la striscia della maniglia. Non e' aria: senza, l'angolo
    -- in basso cadrebbe dentro l'ultima sezione - la tavola dei simboli si
    -- prende i clic - e la maniglia non si potrebbe nemmeno afferrare.
    self:setHeight(y - GAP + PAD + m.grip)
end

function NW_Panel:placeStrip()
    local m = self.metrics
    local PAD, SLOT, SLOT_GAP = m.pad, m.slot, m.slotGap
    local per = self:slotsPerRow()
    local innerW = self.width - PAD * 2
    local inRow = math.min(per, math.max(1, #self.slotButtons))
    local span = inRow * SLOT + (inRow - 1) * SLOT_GAP
    local x0 = PAD + math.floor((innerW - span) / 2)
    for i, b in ipairs(self.slotButtons) do
        local col = (i - 1) % per
        local row = math.floor((i - 1) / per)
        b:setX(x0 + col * (SLOT + SLOT_GAP))
        b:setY(self.stripY + row * (SLOT + SLOT_GAP))
    end
end

function NW_Panel:slotsPerRow()
    local m = self.metrics
    return math.max(1, math.floor((self.width - m.pad * 2 + m.slotGap) / (m.slot + m.slotGap)))
end

-- ---------------------------------------------------------------------------
-- Inventory
-- ---------------------------------------------------------------------------

--- The character is asked for, never cached: ISWorldMap assigns it AFTER the
--- panel is built, so a copy taken at build time stays nil forever - which is
--- why the strip came up empty with a pen in the bag.
function NW_Panel:player()
    local s = self.surface
    if s.getPlayer then return s.getPlayer() end
    return s.player
end

function NW_Panel:rebuildStrip()
    for _, b in ipairs(self.slotButtons) do self:removeChild(b) end
    self.slotButtons = {}
    local SLOT = self.metrics.slot
    for i, tool in ipairs(self.tools) do
        local b = ISButton:new(0, 0, SLOT, SLOT, "", self, NW_Panel.onSlot)
        b:initialise()
        b:instantiate()
        b:setDisplayBackground(false)
        b.nwIndex = i
        b.render = function() end -- painted by the panel
        -- IL ROVESCIO DELLA MATITA NON STA PIU' SUL TASTO DESTRO. Il tooltip
        -- diceva "destro per cancellare", e il destro sulla MAPPA sposta la
        -- vista: chi lo leggeva cliccava sulla mappa e la vedeva scivolare via.
        -- Adesso punta e gomma si scelgono come i colori della penna a cinque
        -- inchiostri, dal selettore che si apre sul tasto (NW_Panel:onSlot).
        NW_Tooltip.attach(b, tool.name or "")
        self:addChild(b)
        self.slotButtons[i] = b
    end
    self:layout()
end

--- Walks every container the player carries, so it runs on a timer.
function NW_Panel:refreshTools()
    local found = NW_Tools.scanTools(self:player())

    local changed = #found ~= #self.tools
    if not changed then
        for i, t in ipairs(found) do
            if t.type ~= self.tools[i].type then changed = true break end
        end
    end

    self.tools = found

    -- SENZA UNA PENNA NON C'E' UN INCHIOSTRO. `currentInk` si ricordava l'ultimo
    -- colore scelto anche dopo che l'oggetto che lo dava era finito per terra:
    -- con in mano solo una gomma, o con niente, il tasto "disegna" continuava a
    -- scrivere in rosso con una penna rossa che non c'era piu'.
    --
    -- Non basta "c'e' ancora una penna": con una blu in tasca e la gomma in mano,
    -- il rosso della penna buttata restava sotto il tasto "disegna". Conta che
    -- QUEL colore lo dia ancora qualcosa.
    local held = false
    for _, t in ipairs(found) do
        for _, id in ipairs(t.inks) do
            if id == self.currentInk then held = true break end
        end
        if held then break end
    end
    if not held and self.currentInk ~= nil then
        self.currentInk = nil
        if self.surface.onInk then self.surface.onInk(nil, self.erasing) end
    end

    if changed then
        self:rebuildStrip()
        local keep
        for i, t in ipairs(self.tools) do
            if t.type == self.selectedType then keep = i end
        end
        self:selectTool(keep or (self.tools[1] and 1 or nil))
    end
end

--- La gomma in mano. Si ricorda cosa si stava facendo, per tornarci quando la
--- gomma si posa o si gira la matita sulla punta.
function NW_Panel:startErasing()
    if self.currentTool ~= "erase" then self.toolBeforeErase = self.currentTool end
    self.erasing = true
    self:setTool("erase")
    if self.surface.onTool then self.surface.onTool("erase") end
    if self.surface.onInk then self.surface.onInk(self.currentInk, true) end
end

--- Posa quello che si ha in mano: niente strumento, niente gomma.
---
--- A MANI VUOTE LA MAPPA SI TRASCINA COL SINISTRO, come in vanilla (NW_Map), ed
--- e' la ragione per cui posare deve essere un gesto a portata: si ripreme la
--- gomma che si sta usando, o lo strumento acceso nella fila.
function NW_Panel:putDown()
    self.erasing = false
    self.toolBeforeErase = nil
    self:setTool(nil)
    if self.surface.onTool then self.surface.onTool(nil) end
end

--- `erase` prende in mano lo strumento dalla parte della gomma.
---
--- E' un argomento e non una funzione a parte perche' prendere in mano uno
--- strumento e' una cosa sola, e averne due versioni vorrebbe dire ricordarsi
--- di aggiornarle tutte e due ogni volta che cambia cosa vuol dire "in mano".
function NW_Panel:selectTool(index, erase)
    self.selected = index
    local tool = index and self.tools[index] or nil
    self.selectedType = tool and tool.type or nil
    if not tool then
        -- LA BORSA E' VUOTA, e chi disegna deve saperlo. Prima si tornava zitti:
        -- il pannello scriveva "niente con cui scrivere" mentre la mappa, a cui
        -- nessuno aveva detto niente, continuava a disegnare con l'ultimo
        -- inchiostro e con l'ultimo strumento in mano.
        self.currentInk = nil
        self.erasing = false
        if self.currentTool then
            self:setTool(nil)
            if self.surface.onTool then self.surface.onTool(nil) end
        end
        if self.surface.onInk then self.surface.onInk(nil, false) end
        return
    end

    if erase and hasRubberEnd(tool) then
        self:startErasing()
    elseif #tool.inks > 0 then
        local keep
        for _, id in ipairs(tool.inks) do
            if id == self.currentInk then keep = id end
        end
        self.currentInk = keep or tool.inks[1]
        self.erasing = false
        -- DALLA GOMMA SI TORNA A QUELLO CHE SI FACEVA. Girare la matita sulla
        -- punta, o prendere una penna mentre si cancellava, lasciava in mano lo
        -- strumento "cancella": si sceglieva di scrivere e si continuava a
        -- cancellare. Si torna allo strumento di prima, e se prima non c'era
        -- niente a "disegna", che e' quello per cui si prende una penna.
        if self.currentTool == "erase" then
            local back = self.toolBeforeErase or "draw"
            -- Senza disegno a mano libera (opzione sandbox) la penna non ha
            -- un "disegna" a cui tornare: si resta a mani vuote.
            if back == "draw" and not NW_Net.freehandAllowed() then back = nil end
            self.toolBeforeErase = nil
            self:setTool(back)
            if self.surface.onTool then self.surface.onTool(back) end
        end
        if self.surface.onInk then self.surface.onInk(self.currentInk, false) end
    else
        -- Picking up the rubber IS choosing to erase: the tool in hand is the
        -- mode, there is no separate erase button to find.
        self:startErasing()
    end
    self.widthSlider.previewInk = self.erasing
        and { r = 0.75, g = 0.75, b = 0.78 } or NW.inkById(self.currentInk)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function NW_Panel:onClose()
    -- I selettori aperti se ne vanno con chi li ha aperti: un pannello di
    -- condivisione che sopravvive alla finestra che stava configurando resta a
    -- mezz'aria sopra il gioco, e configura una cosa che non si vede piu'.
    NW_SharePanel.closeAll()
    if self.surface.onClose then self.surface.onClose() end
end

function NW_Panel:onWorldMap()
    if self.surface.onWorldMap then self.surface.onWorldMap() end
end

--- Accende il velo per inquadrare. Il pannello si toglie di mezzo da solo:
--- durante l'inquadratura il mouse ha un significato solo, e un pannello che
--- resta cliccabile sopra il velo sarebbe una trappola.
function NW_Panel:onCrop()
    local mapUI = self.surface.getMapUI and self.surface.getMapUI()
    if not mapUI then return end
    NW_SharePanel.closeAll()
    NW_Framer.open(mapUI, self:player(), self.nwScale)
end

--- Porta sulla propria mappa i segni di quella che si sta leggendo.
---
--- SI CHIEDE, e la domanda e' il punto: aprire una mappa trovata per terra non
--- deve travasare niente da solo. Il rettangolo invece si svela comunque - una
--- mappa letta si conosce, e' quello che fa anche vanilla.
function NW_Panel:onGrab()
    local item = self.surface.getMapItem and self.surface.getMapItem()
    if not item then return end
    local player = self:player()
    local ink, sym = NW_Cartography.transfer(item, player)
    NW_Sound.note(player)
    -- La nuvoletta sopra il personaggio: e' il modo del gioco di dire che una
    -- cosa e' successa, e non chiede di chiudere niente. Senza, il travaso
    -- riuscito e quello a vuoto - una mappa gia' travasata non aggiunge niente
    -- - sarebbero lo stesso silenzio.
    pcall(function()
        player:setHaloNote(getText("IGUI_NW_MapTaken", tostring(ink + sym)),
            255, 255, 255, 300)
    end)
    if NW_NetClient and NW_NetClient.verbose then
        print("NW_Panel: travasati " .. ink .. " tratti, " .. sym .. " simboli")
    end

    -- E PORTACI DOVE I SEGNI COMPAIONO. Travasare e restare a guardare il
    -- foglio e' meta' gesto: i simboli si posano sulla mappa del mondo, che in
    -- questo momento e' chiusa, quindi da fuori non succede niente di visibile
    -- e si e' costretti a fidarsi. `toWorldMap` dell'ospite centra sui confini
    -- della mappa che si sta leggendo - e per una mappa annotata quei confini
    -- SONO il ritaglio - quindi si arriva esattamente sopra i segni appena
    -- arrivati, e li si vede posarsi (NW_Cartography.drainPending, che gira
    -- proprio all'apertura della mappa del mondo).
    if self.surface.onWorldMap then self.surface.onWorldMap() end
end

--- Come nasceranno i prossimi segni: stesi o dritti. Quelli gia' posati non si
--- toccano - ognuno tiene la prospettiva con cui e' nato (NW_Ink.dressMark).
function NW_Panel:onIso()
    NW.setMarksFollowPerspective(not NW.marksFollowPerspective())
end

function NW_Panel:onShare()
    local b = self.shareBtn
    NW_SharePanel.open(self:getAbsoluteX() + b:getX(),
        self:getAbsoluteY() + b:getY() + b:getHeight() + 4, self.nwScale)
end

--- Le due facce della matita, come scelte del selettore.
---
--- SOLO SULLA MATITA, e non e' una restrizione arbitraria: una penna non ha il
--- rovescio e una gomma non ha la punta. Il disegno delle due icone dice gia'
--- quale parte si prende in mano: la punta scrive, il fondo con la gommetta
--- cancella.
---
--- La punta ha il colore della grafite, come la casella della matita; il fondo
--- con la gomma non scrive, e resta grigio come la casella di una gomma.
local PENCIL_SIDES = {
    { id = "write", icon = "PencilWrite.png", label = "IGUI_NW_InkPencil",
      fill = NW.inkById("pencil").slot },
    { id = "erase", icon = "PencilErase.png", label = "IGUI_NW_Eraser" },
}

function NW_Panel:onSlot(button)
    local tool = self.tools[button.nwIndex]
    if not tool then return end
    local btn = self.slotButtons[button.nwIndex]

    -- LA GOMMA CHE SI STA USANDO, RIPREMUTA, SI POSA. E' il modo di tornare a
    -- mani vuote dalla gomma, che nella fila degli strumenti non ha un tasto da
    -- spegnere: a mani vuote la mappa si trascina col sinistro.
    if self.erasing and self.selected == button.nwIndex and #tool.inks == 0 then
        self:putDown()
        return
    end

    -- La matita: si prende in mano sulla punta e si apre il selettore per
    -- girarla. Se la si stava gia' usando come gomma, ripremerla la posa - come
    -- la gomma qui sopra - invece di riaprire il selettore.
    if hasRubberEnd(tool) then
        if self.erasing and self.selected == button.nwIndex then
            self:putDown()
            return
        end
        self:selectTool(button.nwIndex, false)
        NW_InkPopup.open(self:getAbsoluteX() + btn:getX(),
            self:getAbsoluteY() + btn:getY() + self.metrics.slot + 2,
            PENCIL_SIDES, "write",
            function(id) self:selectTool(button.nwIndex, id == "erase") end,
            self.nwScale)
        return
    end

    self:selectTool(button.nwIndex)

    -- A multi-colour item opens its palette rather than cycling: clicking four
    -- times to get back to red is not a choice.
    --
    -- Al PRIMO clic, non al secondo. Aprirla solo ri-cliccando uno strumento
    -- gia' scelto e' un gesto che nessuno indovina: si prendeva la penna, non
    -- succedeva niente di visibile, e la si posava. Prendere in mano una penna
    -- a cinque colori e' gia' chiedere quale.
    if #tool.inks > 1 then
        NW_InkPopup.open(self:getAbsoluteX() + btn:getX(),
            self:getAbsoluteY() + btn:getY() + self.metrics.slot + 2,
            tool.inks, self.currentInk,
            function(id)
                self.currentInk = id
                self.widthSlider.previewInk = NW.inkById(id)
                if self.surface.onInk then self.surface.onInk(id, false) end
            end,
            self.nwScale)
    end
end

function NW_Panel:onTool(button)
    local id = button.internal
    if self.currentTool == id then id = nil end
    -- Uno strumento della fila rimette giu' la gomma: in mano ce n'e' uno solo.
    if id ~= "erase" then
        self.erasing = false
        self.toolBeforeErase = nil
    end
    self:setTool(id)
    if self.surface.onTool then self.surface.onTool(id) end
end

function NW_Panel:setTool(id)
    self.currentTool = id
    for toolId, b in pairs(self.toolButtons) do
        NW_Style.setButtonActive(b, toolId == id)
    end
    -- Each tool brings its own controls, and nothing else. Size and turn are
    -- done with the move/rotate/edit buttons, so a slider for them would be a
    -- second way to do one job.
    self.widthSlider:setVisible(id == "draw")
    self.symbolPicker:setVisible(id == "symbol")
    self:layout()
end

function NW_Panel:onWidth(value)
    self.brushWidth = value
    if self.surface.onWidth then self.surface.onWidth(value) end
end

-- ---------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------

function NW_Panel:prerender()
    local m = self.metrics
    local PAD, BOX, HEADER_H = m.pad, m.box, m.headerH

    NW_Style.drawWindow(self, 0, 0, self.width, self.height, HEADER_H)

    -- Group boxes go here, not in render: children paint between prerender and
    -- render, so a box drawn later would sit on top of its own buttons.
    local bx = PAD - BOX
    local bw = self.width - bx * 2
    if self.stripBox then
        NW_Style.drawGroup(self, bx, self.stripBox.y, bw, self.stripBox.h)
    end
    if self.actionBox then
        NW_Style.drawGroup(self, bx, self.actionBox.y, bw, self.actionBox.h)
        NW_Style.drawRule(self, PAD + BOX, self.ruleY, self.width - (PAD + BOX) * 2)
    end
    if self.sliderBox then
        NW_Style.drawGroup(self, bx, self.sliderBox.y, bw, self.sliderBox.h)
    end

    self:watchFreehand()
    if self.shareBtn and self.shareBtn:isVisible() ~= self:showsShare() then
        self.shareBtn:setVisible(self:showsShare())
    end
    -- L'AEROPLANINO RESTA ACCESO finche' quello che scrivi non e' solo tuo.
    -- E' l'unica spia di uno stato che dura: la scelta e' nella modData e
    -- sopravvive alla chiusura della mappa e all'uscita dal gioco, quindi senza
    -- una luce accesa da qualche parte si torna a giocare il giorno dopo
    -- convinti di scrivere per se' mentre si sta scrivendo per il server. Si
    -- spegne su "solo io", che e' l'unico modo di essere davvero privati.
    if self.shareBtn then
        NW_Style.setButtonActive(self.shareBtn, not NW_Share.isPrivate(self:player()))
    end
    if self.isoBtn then
        local iso = NW.marksFollowPerspective()
        NW_Style.setButtonActive(self.isoBtn, iso)
        if self.isoBtn.nwIso ~= iso then
            self.isoBtn.nwIso = iso
            NW_Style.setButtonIcon(self.isoBtn,
                NW_Style.tex(NW.ICONS .. (iso and "ViewIsometric.png" or "ViewTop.png")))
        end
    end
    -- La carta si consuma e si raccoglie mentre la mappa e' aperta, quindi la
    -- condizione del ritaglio si riguarda a ogni fotogramma come le altre.
    if self.cropBtn and self.cropBtn:isVisible() ~= self:showsCrop() then
        self.cropBtn:setVisible(self:showsCrop())
    end
    if self.grabBtn and self.grabBtn:isVisible() ~= self:showsGrab() then
        self.grabBtn:setVisible(self:showsGrab())
    end
    -- UNO DEI DUE, MAI TUTTI E DUE. Su una delle nostre mappe "rivela sulla
    -- mappa" e "porta sulla mia mappa" sono lo stesso gesto visto da due lati -
    -- il travaso svela il rettangolo per primo - e affiancarli vorrebbe dire
    -- due tasti con la stessa faccia che fanno quasi la stessa cosa, cioe' far
    -- fermare chi legge a chiedersi quale dei due voleva.
    if self.worldBtn then
        local hide = self:showsGrab()
        if self.worldBtn:isVisible() == hide then self.worldBtn:setVisible(not hide) end
    end

    local btn = NW_Style.headerButtonSize(HEADER_H)
    local hy = math.floor((HEADER_H - btn) / 2)
    local gap = NW_Style.headerGap(HEADER_H)
    self.closeBtn:setX(self.width - btn - NW_Style.headerPadding(HEADER_H))
    self.closeBtn:setY(hy)
    -- Gli altri si accodano verso sinistra, ognuno dietro a quello prima: cosi'
    -- la X resta sempre nell'angolo, che e' dove la mano la cerca.
    local last = nil
    for _, b in ipairs(self:headerButtons()) do
        if last then b:setX(last:getX() - btn - gap) end
        b:setY(hy)
        last = b
    end

    -- The layout depends on things that change outside of it: the room the map
    -- allows, how tall the symbol sheet decided to be, which sections are
    -- showing. Chasing each of those with its own call left the first opening
    -- of the sheet with a grown inner box inside a panel that had not grown.
    -- So the panel watches those values instead, and re-lays itself out the
    -- frame any of them moves - whatever caused it.
    local sig = table.concat({
        tostring(self.symbolPicker:isVisible()),
        tostring(self.symbolPicker:getHeight()),
        tostring(self.widthSlider:isVisible()),
        tostring(#self.tools),
        tostring(self.maxHeight),
        tostring(self.width),
    }, "|")
    if sig ~= self.layoutSig then
        self.layoutSig = sig
        self:layout()
    end

    local now = getTimestampMs()
    if not self.lastScan or now - self.lastScan > RESCAN_MS then
        self.lastScan = now
        self:refreshTools()
    end
end

--- La casella di uno strumento: lo slot di Clean HotBar, riempito del colore
--- di quello che scrive, e sopra l'icona dell'oggetto.
---
--- IL COLORE E' IL FONDO, non piu' una lineetta in basso. Una penna a quattro
--- colori divide la casella in quattro colonne e accende quella in uso; una
--- gomma non ha inchiostro e resta grigia; la matita girata sulla gomma perde
--- la grafite e mostra la gommetta nell'angolo.
function NW_Panel:drawSlot(btn, tool, selected)
    local SLOT = self.metrics.slot
    local x, y = btn:getX(), btn:getY()

    local fills, current = {}, nil
    for i, id in ipairs(tool.inks) do
        local ink = NW.inkById(id)
        fills[i] = ink.slot or ink
        if id == self.currentInk then current = i end
    end
    -- Fuori di mano nessuna colonna e' "in uso": tutte piene, tutte uguali.
    if not selected then current = nil end
    NW_Style.drawSlot(self, x, y, SLOT, SLOT, {
        fills = fills,
        current = current,
        selected = selected,
        hover = btn:isMouseOver(),
        -- La matita girata sulla gomma: niente grafite, la gommetta nell'angolo.
        badge = (selected and self.erasing and #tool.inks > 0)
            and NW_Style.tex(NW.ICONS .. "PencilErase.png") or nil,
    })

    if tool.tex then
        -- Item icons are not square (a pen is tall and thin): fitting one into
        -- a square box stretched it. Inscribe it instead, keeping its ratio.
        local pad = math.max(3, math.floor(SLOT * 0.15))
        local box = SLOT - pad * 2
        local iw, ih = tool.tex:getWidth(), tool.tex:getHeight()
        local k = math.min(box / math.max(1, iw), box / math.max(1, ih))
        local dw, dh = math.floor(iw * k), math.floor(ih * k)
        self:drawTextureScaled(tool.tex, x + math.floor((SLOT - dw) / 2),
            y + math.floor((SLOT - dh) / 2), dw, dh, 1, 1, 1, 1)
    end
end

function NW_Panel:render()
    local m = self.metrics
    local PAD, HEADER_H, ROW_H, SLOT = m.pad, m.headerH, m.rowH, m.slot

    local pad = NW_Style.headerPadding(HEADER_H)
    local iconSize = NW_Style.headerIconSize(HEADER_H)

    local pen = NW_Style.tex(NW.ICONS .. "Pen.png")
    local tx = pad
    if pen then
        self:drawTextureScaled(pen, pad, math.floor((HEADER_H - iconSize) / 2),
            iconSize, iconSize, 1, NW_Style.text.r, NW_Style.text.g, NW_Style.text.b)
        tx = pad + iconSize + NW_Style.headerGap(HEADER_H)
    end
    self:drawText(getText("IGUI_NW_Title"), tx, math.floor((HEADER_H - m.fontBigH) / 2),
        NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, m.fontBig)

    if not self.renaming then
        -- Il nome si accorcia prima di finire sotto al tasto rinomina: un nome
        -- lungo che passa dietro a un'icona sembra un difetto, non un nome lungo.
        local title = self.surface.title or ""
        local room = (self.titleLimit or self.width) - PAD
        local tm = getTextManager()
        if tm:MeasureStringX(m.font, title) > room then
            while #title > 1 and tm:MeasureStringX(m.font, title .. "...") > room do
                title = title:sub(1, #title - 1)
            end
            title = title .. "..."
        end
        self:drawText(title, PAD,
            self.subjectY + math.floor((ROW_H - m.fontH) / 2),
            NW_Style.dim.r, NW_Style.dim.g, NW_Style.dim.b, 1, m.font)
    end

    if #self.tools == 0 then
        self:drawText(getText("IGUI_NW_NoPen"), PAD + 2,
            self.stripY + math.floor((SLOT - m.fontH) / 2),
            0.85, 0.45, 0.45, 1, m.font)
    else
        for i, btn in ipairs(self.slotButtons) do
            local tool = self.tools[i]
            if tool then self:drawSlot(btn, tool, i == self.selected) end
        end
    end

    self:drawGrip()
end

-- ---------------------------------------------------------------------------
-- La maniglia d'angolo
-- ---------------------------------------------------------------------------
--
-- STA DALLA PARTE IN CUI IL PANNELLO CRESCE. Su un foglio il pannello e'
-- appoggiato al fianco destro della carta e cresce verso destra: maniglia in
-- basso a destra, come CleanUI e come tutte le Neat. Sulla mappa del mondo e'
-- incollato all'angolo destro dell'interfaccia e cresce verso sinistra:
-- maniglia in basso a sinistra, o sarebbe ferma sotto il dito mentre il
-- pannello si allunga dall'altra parte.
--
-- PICCOLA E FISSA: sedici pixel, come NR_ResizeWidget di Rocco e come la barra
-- di XP Drop, che ha questa nota nel suo codice. Su un pannello tirato al
-- doppio una maniglia doppia diventa un pulsante.
--
-- LA FIGURA E' SPECCHIATA NEI PIXEL, non a runtime. Ribaltarla con
-- drawTextureAllPoint non disegnava niente: specchiare inverte il verso di
-- avvolgimento del quadrilatero, e un quadrilatero al contrario il motore lo
-- scarta. Da fuori sembrava una striscia vuota in fondo al pannello - la
-- maniglia "scollegata" della segnalazione. E lasciarla dritta nell'angolo
-- sinistro non andava bene lo stesso: una freccia che punta dalla parte
-- sbagliata dice il contrario di quello che fa. Percio' ci sono due file,
-- ResizeGrip.png e ResizeGripLeft.png, e il secondo lo produce
-- strumenti/arte/genera-maniglia-sinistra.js specchiando il primo.
--
-- IL CONTO E' IN COORDINATE DI SCHERMO (getMouseX globale). In coordinate del
-- pannello si morderebbe la coda: il pannello che si allarga si sposta a
-- sinistra della stessa quantita', un pixel di trascinamento ne diventerebbe
-- due, e la misura schizzerebbe al massimo al primo tocco.

--- La scatola della maniglia, in coordinate del pannello.
function NW_Panel:gripBox()
    local g = self.metrics.grip
    local x = self.growLeft and 2 or (self.width - g - 2)
    return x, self.height - g - 2, g
end

function NW_Panel:drawGrip()
    local x, y, g = self:gripBox()
    -- Due file, non una girata a runtime: la figura per l'angolo sinistro e'
    -- gia' specchiata nei pixel (strumenti/arte/genera-maniglia-sinistra.js).
    local tex = NW_Style.tex(NW.ICONS ..
        (self.growLeft and "ResizeGripLeft.png" or "ResizeGrip.png"))
    local a = self.resizing and 1 or (self.gripOver and 0.85 or 0.5)
    if tex then
        self:drawTextureScaled(tex, x, y, g, g, a,
            NW_Style.dim.r, NW_Style.dim.g, NW_Style.dim.b)
        return
    end
    -- Senza la figura: tre trattini in diagonale, la stessa sagoma. Questi si
    -- possono specchiare, perche' sono rettangoli disegnati da noi e non un
    -- quadrilatero con un verso.
    local th = math.max(1, math.floor(g * 0.12))
    for i = 1, 3 do
        local len = math.floor(g * (0.30 + 0.22 * (i - 1)))
        local oy = y + g - i * math.floor(g * 0.28)
        local ox = self.growLeft and x or (x + g - len)
        self:drawRect(ox, oy, len, th, a, 0.92, 0.92, 0.92)
    end
end

function NW_Panel:overGrip(x, y)
    local gx, gy, g = self:gripBox()
    return x >= gx - 3 and x <= gx + g + 3 and y >= gy - 3 and y <= gy + g + 3
end

-- Consume the mouse so a click meant for the panel never reaches the map
-- behind it, which would pan or drop a symbol.
function NW_Panel:onMouseDown(x, y)
    if self:overGrip(x, y) then
        self.resizing = true
        self.grabScale = self.nwScale
        self.grabWidthF = self.widthF
        self.grabW = self.width
        self.grabX = getMouseX()
        self.grabY = getMouseY()
        -- Il mouse resta nostro fino a che non si molla. Senza, appena il
        -- puntatore passa sopra a un tasto del pannello - e rimpicciolendo ci
        -- passa subito - il movimento va a lui e il ridimensionamento si
        -- pianta a meta'. E' quello che fa ISResizeWidget di vanilla.
        self:setCapture(true)
    end
    return true
end

function NW_Panel:onMouseUp(x, y)
    if self.resizing then
        self.resizing = false
        self:setCapture(false)
        -- Adesso, non a ogni pixel: la tavola dei simboli si rifa' da capo e
        -- la misura si scrive sul disco. Una volta per trascinamento.
        local scaled = math.abs(self.nwScale - (self.grabScale or 1)) > 0.0005
        local widened = math.abs((self.widthF or 1) - (self.grabWidthF or 1)) > 0.0005
        if scaled then self:setScale(self.nwScale, false) end
        if widened then self:setWidthFactor(self.widthF, false) end
        if (scaled or widened) and self.surface.onResized then
            self.surface.onResized(self)
        end
    end
    return true
end

function NW_Panel:onMouseUpOutside(x, y)
    return self:onMouseUp(x, y)
end

function NW_Panel:onMouseMove(dx, dy)
    self.gripOver = self:overGrip(self:getMouseX(), self:getMouseY())
    if self.resizing then
        -- DUE DIREZIONI, DUE MISURE, come una finestra dell'inventario.
        --
        -- IN ORIZZONTALE LA LARGHEZZA. Si tira verso l'esterno e si allarga:
        -- verso destra su un foglio, verso sinistra sulla mappa del mondo, che
        -- e' la parte in cui quel pannello ha spazio per crescere. In tutt'e due
        -- i casi il dito va dalla parte della maniglia, ed e' per questo che la
        -- maniglia sta di la'.
        --
        -- IN VERTICALE LA MISURA DI QUELLO CHE C'E' DENTRO. Prima un numero solo
        -- faceva tutte e due le cose, e ingrandire le lettere per leggerle a 4K
        -- voleva dire allargare il pannello nella stessa proporzione: a scala 2
        -- si mangiava mezza mappa. Adesso tirando in giu' crescono tasti e
        -- caratteri, e il pannello si allarga solo di quanto serve alla sua
        -- riga di tasti piu' lunga. Il resto va a capo.
        local dx = getMouseX() - (self.grabX or 0)
        if self.growLeft then dx = -dx end
        local dy = getMouseY() - (self.grabY or 0)
        self:setScale((self.grabScale or 1) + dy / SCALE_DRAG_PX, true)
        self:setWidthFactor(((self.grabW or self.width) + dx) / self.baseWidth, true)
    end
    return true
end

function NW_Panel:onMouseMoveOutside(dx, dy)
    self.gripOver = false
    if self.resizing then return self:onMouseMove(dx, dy) end
end

function NW_Panel:onMouseWheel(del) return true end

-- ---------------------------------------------------------------------------

--- `width` e' la larghezza DI PROGETTO, quella a scala 1: la misura vera esce
--- da li' per la scala che il giocatore ha scelto tirando la maniglia.
function NW_Panel:new(x, y, surface, width)
    local base = width or NW.PANEL_W
    local scale = NW.panelScale()
    local o = ISPanel.new(self, x, y, NW.panelWidth(base, scale), 200)
    o.baseWidth = base
    o.nwScale = scale
    o.widthF = NW.panelWidthFactor()
    -- Da che parte cresce, e quindi da che parte sta la maniglia. Lo dice chi
    -- lo ospita: la mappa del mondo lo tiene nell'angolo destro dell'interfaccia
    -- e gli lascia spazio a sinistra; accanto a un foglio o a una mappa di carta
    -- cresce verso destra.
    o.growLeft = (surface and surface.growLeft) == true
    o.surface = surface or {}
    o.background = false
    o.moveWithMouse = false
    o.tools = {}
    o.slotButtons = {}
    o.selected = nil
    o.selectedType = nil
    o.currentInk = NW.INKS[1].id
    o.currentTool = nil
    o.currentSymbol = nil
    o.erasing = false
    o.brushWidth = NW.BRUSH.DEFAULT
    return o
end
