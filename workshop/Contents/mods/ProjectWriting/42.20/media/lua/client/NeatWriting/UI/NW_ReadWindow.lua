--[[ ============================================================================
    NW_ReadWindow - la cornice di lettura, costruita e non vestita.

    PERCHE' RIFATTA. Prima la finestra di vanilla veniva vestita: alle sue nodi
    PZAPI si davano le nostre texture, i nostri colori e le nostre misure. Ha
    funzionato per quasi tutto e ha continuato a non funzionare per una cosa: i
    bordi. Una nostra cornice e' una NinePatchTexture - quattro angoli che non si
    deformano mai e un centro che si allunga - e un nodo PZAPI non la sa
    disegnare: gli si puo' dare la texture e uno slice, ma quello che ne esce
    non e' un nine-patch nostro. Da li' i bordi irregolari in alto e nell'header,
    che nessuna misura di slice ha mai raddrizzato del tutto.

    Qui la cornice e' un ISPanel, cioe' il posto dove NW_Style.drawWindow -
    la stessa riga che disegna il pannello Writing, la configurazione di XP Drop
    e ogni altra finestra della famiglia - funziona senza trucchi.

    COSA RESTA DI VANILLA: il foglio. E' una scena di testo ricco - texture
    ruotate, caratteri SDF, pivot per elemento - che disegna il sistema di nodi
    del gioco. Rifarne il lettore vorrebbe dire riscrivere quel parser per
    ridisegnare la stessa identica carta. La finestra di vanilla resta quindi
    viva ma spogliata di tutto: niente barra, niente fila di tasti, niente
    striscia in fondo. E' solo il foglio, e noi le mettiamo la cornice attorno.

    COME STANNO UNA SOPRA L'ALTRA. La cornice non e' sotto per fortuna
    dell'ordine in cui sono state aggiunte: il foglio e' `setAlwaysOnTop(true)`
    e la cornice no. E' un meccanismo dichiarato, non un caso.

    L'HEADER E' QUELLO DELLA FAMIGLIA: icona a sinistra, titolo accanto, i tasti
    a destra e la X rossa nell'angolo, alle misure che NW_Style ricava
    dall'altezza dell'header. I tasti mappa sono nostri e chiamano il
    `onLeftClick` dei nodi di vanilla, che e' dove sta la funzione vera.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Style"
require "NeatWriting/UI/NW_Tooltip"
require "NeatWriting/UI/NW_Transcript"

NW_ReadWindow = ISPanel:derive("NW_ReadWindow")

local FONT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local HEADER_H = math.floor(FONT_MEDIUM * 1.5)
local PAD = 8            -- la cornice di pannello attorno al foglio
local GRIP = 16          -- la maniglia d'angolo
local FOOT = GRIP + 4    -- la striscia in fondo che la contiene
local MIN_SHEET = 160
local MAX_MAPS = 5
-- L'aria che resta fra la finestra e il bordo dello schermo. Serve a una cosa
-- sola ma indispensabile: la maniglia d'angolo deve restare raggiungibile.
local SCREEN_AIR = 24

-- ---------------------------------------------------------------------------
-- Il foglio di vanilla, visto da qui
-- ---------------------------------------------------------------------------

--- Il nodo che disegna la carta.
local function sheetNode(pm)
    local body = pm and pm.children and pm.children.body
    return body and body.children and body.children.printMedia or nil
end

--- La misura naturale del foglio, senza ingrandimento. Si legge una volta: e'
--- quello che serve per ricavare la scala da una larghezza.
local function baseSize(pm)
    local node = sheetNode(pm)
    if not node then return nil end
    local w = tonumber(node.width) or 0
    local h = tonumber(node.height) or 0
    if w <= 0 or h <= 0 then return nil end
    return w, h
end

--- Il foglio a questa larghezza, tenendo le proporzioni.
local function scaleSheet(self, sheetW)
    local node = sheetNode(self.pm)
    if not node or not self.baseW then return end
    local s = sheetW / self.baseW
    pcall(function()
        node:setScaleX(s)
        node:setScaleY(s)
    end)
    self.sheetW = math.floor(self.baseW * s)
    self.sheetH = math.floor(self.baseH * s)
end

-- ---------------------------------------------------------------------------
-- Costruzione
-- ---------------------------------------------------------------------------

function NW_ReadWindow:createChildren()
    local btn = NW_Style.headerButtonSize(HEADER_H)

    -- La X: rossa e sempre accesa, come ogni chiusura della famiglia.
    self.closeBtn = NW_Style.newSquareButton(0, 0, btn, NW_Style.iconClose(),
        self, NW_ReadWindow.onClose, NW_Style.close)
    self:addChild(self.closeBtn)
    -- La chiusura usa la chiave di vanilla: e' gia' tradotta in tutte le
    -- lingue che il gioco spedisce, e una nostra sarebbe la stessa parola.
    NW_Tooltip.attach(self.closeBtn, getText("UI_Close"))

    -- La trascrizione: il testo della stampa in chiaro, in un pannello accanto.
    -- Si costruisce sempre e si mostra solo se la stampa ne ha una (NW_Transcript).
    self.transcriptBtn = NW_Style.newSquareButton(0, 0, btn,
        NW_Style.tex(NW.ICONS .. "Info.png"), self, NW_ReadWindow.onTranscript)
    self:addChild(self.transcriptBtn)
    NW_Tooltip.attach(self.transcriptBtn, getText("IGUI_NW_Transcript"))
    self.transcriptBtn:setVisible(false)

    -- I tasti mappa: uno per ogni luogo che questo documento sa svelare. La
    -- funzione e' quella di vanilla - il nodo la porta con se' - e noi ci
    -- mettiamo solo il tasto attorno.
    -- Un tasto per ogni nodo che esiste, non per ogni nodo acceso adesso.
    --
    -- Chi apre una stampa DALLA MAPPA li spegne tutti e cinque subito dopo
    -- instantiate - cioe' dopo che siamo passati di qui - quindi guardarli una
    -- volta sola darebbe cinque tasti che non svelano niente. Si costruiscono
    -- tutti e si accendono a ogni frame guardando il nodo: e' lui che sa.
    self.mapBtns = {}
    local strip = self.pm and self.pm.children and self.pm.children.bottomButtons
    for i = 1, MAX_MAPS do
        local node = strip and strip.children and strip.children["revealOnMap" .. i]
        if node then
            -- La nostra icona, non `media/textures/Item_Map.png`: quella e'
            -- l'immagine d'inventario di una mappa di carta, disegnata per
            -- stare in una casella accanto a barattoli e martelli, e in
            -- un'intestazione Neat stona come una fotografia in mezzo a dei
            -- pittogrammi. Stessa immagine del tasto "mappa del mondo" del
            -- pannello Writing: la stessa cosa si chiama allo stesso modo.
            local b = NW_Style.newSquareButton(0, 0, btn,
                NW_Style.tex(NW.ICONS .. "WorldMap.png"),
                self, NW_ReadWindow.onReveal)
            b.nwNode = node
            b:setVisible(false)
            self:addChild(b)
            self.mapBtns[#self.mapBtns + 1] = b
            NW_Tooltip.attach(b, getText("IGUI_NW_RevealOnMap"))
        end
    end

    self:syncMaps()
    self:layout()
end

--- Accende i tasti mappa che il documento ha davvero. Torna vero se il conto e'
--- cambiato, cioe' se la fila va rimessa in fila.
---
--- Si legge `node.visible` e non l'oggetto Java: nascondere la striscia che li
--- contiene spegne i figli a schermo ma non tocca il loro flag, che e' proprio
--- quello che ci interessa sapere.
function NW_ReadWindow:syncMaps()
    local shown = 0
    for _, b in ipairs(self.mapBtns) do
        local node = b.nwNode
        local on = node and node.visible == true
        if b:getIsVisible() ~= on then b:setVisible(on) end
        if on then shown = shown + 1 end
    end
    local changed = shown ~= self.nwShownMaps
    self.nwShownMaps = shown
    return changed
end

--- Rimette a posto i tasti dopo ogni cambio di misura.
function NW_ReadWindow:layout()
    local btn = NW_Style.headerButtonSize(HEADER_H)
    local pad = NW_Style.headerPadding(HEADER_H)
    local gap = NW_Style.headerGap(HEADER_H)
    local y = math.floor((HEADER_H - btn) / 2)

    self.closeBtn:setX(self.width - btn - pad)
    self.closeBtn:setY(y)

    local x = self.width - btn - pad
    for _, b in ipairs(self.mapBtns) do
        if b:getIsVisible() then
            x = x - btn - gap
            b:setX(x)
            b:setY(y)
        end
    end
    if self.transcriptBtn and self.transcriptBtn:getIsVisible() then
        x = x - btn - gap
        self.transcriptBtn:setX(x)
        self.transcriptBtn:setY(y)
    end
    -- Dove il titolo deve smettere di scriversi.
    self.titleLimit = x - gap
end

--- Il testo in chiaro della stampa che si sta leggendo. E' quello che vanilla
--- stessa mostra con il suo taccuino: titolo e testo tradotti dal gioco.
function NW_ReadWindow:onTranscript()
    if not self.pm then return end
    NW_Transcript.toggle(self, self.pm.textTitle or self.title, self.pm.textData)
end

-- ---------------------------------------------------------------------------
-- Disegno
-- ---------------------------------------------------------------------------

function NW_ReadWindow:prerender()
    -- Il foglio se n'e' andato per una via che non passa da qui - Esc su di lui,
    -- il personaggio che smette di leggere - e la cornice non ha piu' niente da
    -- incorniciare.
    if not self:alive() then self:onClose() return end

    if self:syncMaps() then self:fit() end

    -- Il tasto della trascrizione c'e' solo se c'e' un testo da mostrare: il
    -- testo arriva sulla finestra di vanilla dopo instantiate, quindi si guarda
    -- qui e non alla costruzione. E il pannello, se e' aperto, segue la cornice.
    local hasText = self.pm and NW_Transcript.available(self.pm.textData)
    if self.transcriptBtn and self.transcriptBtn:getIsVisible() ~= (hasText == true) then
        self.transcriptBtn:setVisible(hasText == true)
        self:fit()
    end
    if self.transcriptBtn then
        NW_Style.setButtonActive(self.transcriptBtn, NW_Transcript.instance ~= nil)
    end
    if NW_Transcript.instance then NW_Transcript.instance:follow(self) end

    NW_Style.drawWindow(self, 0, 0, self.width, self.height, HEADER_H)

    -- Il foglio, dentro il corpo. Si riposiziona a ogni frame perche' la
    -- finestra si puo' spostare, e vanilla non sa di essere dentro qualcosa.
    --
    -- E A OGNI FRAME SI RIMETTE SOPRA. ISReadABook fa, in quest'ordine:
    --     win:instantiate()                  <- la cornice nasce qui dentro
    --     win.javaObj:setAlwaysOnTop(false)  <- e qui viene disfatto
    -- quindi dirlo una volta sola non basta: la riga dopo la nostra lo
    -- rimetterebbe sotto, e il foglio sparirebbe dietro il corpo del pannello.
    local ok = pcall(function()
        local j = self.pm.javaObj
        j:setAlwaysOnTop(true)
        j:setX(self:getAbsoluteX() + PAD)
        j:setY(self:getAbsoluteY() + HEADER_H + PAD)
        -- Solo quando cambia: setWidth su un nodo PZAPI fa girare il suo
        -- onResize, e farlo sessanta volte al secondo per niente e' spreco.
        if self.pm.width ~= self.sheetW or self.pm.height ~= self.sheetH then
            self.pm:setWidth(self.sheetW)
            self.pm:setHeight(self.sheetH)
        end
    end)
    if not ok then self:onClose() end
end

function NW_ReadWindow:render()
    local pad = NW_Style.headerPadding(HEADER_H)
    local iconSize = NW_Style.headerIconSize(HEADER_H)

    -- La rivista, icona della lettura: la stessa del tasto della mappa.
    local icon = NW_Style.tex(NW.ICONS .. "Magazine.png")
    local tx = pad
    if icon then
        self:drawTextureScaled(icon, pad, math.floor((HEADER_H - iconSize) / 2),
            iconSize, iconSize, 1, NW_Style.text.r, NW_Style.text.g, NW_Style.text.b)
        tx = pad + iconSize + NW_Style.headerGap(HEADER_H)
    end

    -- Il titolo si accorcia prima di finire sotto ai tasti. Un nome lungo che
    -- passa dietro a un'icona sembra un difetto, non un nome lungo.
    local title = self.title or ""
    local room = (self.titleLimit or self.width) - tx
    local tm = getTextManager()
    if room > 0 and tm:MeasureStringX(UIFont.Medium, title) > room then
        while #title > 1 and tm:MeasureStringX(UIFont.Medium, title .. "...") > room do
            title = title:sub(1, #title - 1)
        end
        title = title .. "..."
    end
    self:drawText(title, tx, math.floor((HEADER_H - FONT_MEDIUM) / 2),
        NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, UIFont.Medium)

    -- La maniglia d'angolo, la stessa di ogni pannello della famiglia.
    local grip = NW_Style.tex(NW.ICONS .. "ResizeGrip.png")
    local gx, gy = self.width - GRIP - 2, self.height - GRIP - 2
    if grip then
        local a = self.resizing and 1 or 0.6
        self:drawTextureScaled(grip, gx, gy, GRIP, GRIP, a,
            NW_Style.dim.r, NW_Style.dim.g, NW_Style.dim.b)
    end
end

-- ---------------------------------------------------------------------------
-- Mouse: trascinare dall'header, ridimensionare dalla maniglia
-- ---------------------------------------------------------------------------

local function overGrip(self, x, y)
    return x >= self.width - GRIP - 4 and y >= self.height - GRIP - 4
end

function NW_ReadWindow:onMouseDown(x, y)
    self:bringToTop()
    if overGrip(self, x, y) then
        self.resizing = true
        self.grabW = self.sheetW
        self.grabX = x
        return true
    end
    if y <= HEADER_H then
        self.moving = true
        self.grabDX = x
        self.grabDY = y
    end
    return true
end

function NW_ReadWindow:onMouseMove(dx, dy)
    if self.resizing then
        self:resizeTo((self.grabW or self.sheetW) + (self:getMouseX() - (self.grabX or 0)))
        return true
    end
    if self.moving then
        self:setX(self:getX() + self:getMouseX() - (self.grabDX or 0))
        self:setY(self:getY() + self:getMouseY() - (self.grabDY or 0))
        return true
    end
    return false
end

function NW_ReadWindow:onMouseUp(x, y)
    self.resizing = false
    self.moving = false
    return true
end

function NW_ReadWindow:onMouseUpOutside(x, y)
    self.resizing = false
    self.moving = false
end

function NW_ReadWindow:onMouseMoveOutside(dx, dy)
    return self:onMouseMove(dx, dy)
end

--- La rotella ingrandisce il foglio, come faceva la finestra di vanilla.
function NW_ReadWindow:onMouseWheel(del)
    self:resizeTo(math.floor((self.sheetW or 0) * (del > 0 and 0.9 or 1.1)))
    return true
end

--- La larghezza massima del foglio.
---
--- NON e' solo una questione di gusto. Senza tetto la finestra poteva crescere
--- oltre lo schermo, e la maniglia d'angolo finiva fuori: da li' non si poteva
--- piu' rimpicciolire, perche' l'unica cosa che rimpicciolisce era diventata
--- irraggiungibile. Un comando che si puo' usare per andare in un verso solo e'
--- una trappola.
---
--- Tre limiti, e vince il piu' stretto: la larghezza dello schermo, l'altezza
--- dello schermo riportata in larghezza dalle proporzioni del foglio, e il
--- doppio della misura vera della carta - oltre quella una scena disegnata a
--- quella risoluzione si sgrana.
function NW_ReadWindow:maxSheetW()
    if not self.baseW or not self.baseH or self.baseH <= 0 then return MIN_SHEET end
    local sw = getCore():getScreenWidth() - PAD * 2 - SCREEN_AIR * 2
    local sh = getCore():getScreenHeight() - HEADER_H - PAD * 2 - FOOT - SCREEN_AIR * 2
    local byHeight = sh * (self.baseW / self.baseH)
    return math.max(MIN_SHEET, math.min(self.baseW * 2, sw, byHeight))
end

--- Porta il foglio a questa larghezza, dentro i limiti, e rimisura la finestra.
function NW_ReadWindow:resizeTo(w)
    w = math.max(MIN_SHEET, math.min(w, self:maxSheetW()))
    if w == self.sheetW then return end
    scaleSheet(self, w)
    self:fit()
end

-- ---------------------------------------------------------------------------
-- Misure, apertura e chiusura
-- ---------------------------------------------------------------------------

--- La finestra si rimisura sul foglio che contiene.
function NW_ReadWindow:fit()
    self:setWidth(math.max(self.sheetW + PAD * 2, self:minWidth()))
    self:setHeight(HEADER_H + self.sheetH + PAD * 2 + FOOT)

    -- E dentro lo schermo. Una finestra che cresce verso il basso a destra puo'
    -- uscirne anche senza che la si sia mai spostata.
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if self:getX() + self.width > sw then self:setX(math.max(0, sw - self.width)) end
    if self:getY() + self.height > sh then self:setY(math.max(0, sh - self.height)) end

    self:layout()
end

--- La larghezza minima e' l'header sommato: icona, un pezzo di titolo, i tasti.
--- Sotto quella i tasti finirebbero sopra il nome, e nessuno se ne accorgerebbe
--- prima di vederlo.
function NW_ReadWindow:minWidth()
    local btn = NW_Style.headerButtonSize(HEADER_H)
    local pad = NW_Style.headerPadding(HEADER_H)
    local gap = NW_Style.headerGap(HEADER_H)
    local left = pad + NW_Style.headerIconSize(HEADER_H) + gap
    local shown = (self.nwShownMaps or 0) + ((self.transcriptBtn and self.transcriptBtn:getIsVisible()) and 1 or 0)
    local right = pad + btn + shown * (btn + gap)
    return left + 48 + right
end

--- Il foglio c'e' ancora?
---
--- Il primo frame non conta. La cornice nasce dentro instantiate(), cioe' prima
--- che chi ha aperto la finestra abbia finito di sistemarla: se in quell'istante
--- il foglio risultasse non visibile, ci chiuderemmo da soli portandocelo dietro
--- - e il giocatore non vedrebbe niente, senza un errore da nessuna parte.
--- Si comincia a guardare solo dopo averlo visto vivo una volta.
function NW_ReadWindow:alive()
    if not self.pm or not self.pm.javaObj then return false end

    -- Due domande, non una. "E' visibile" non basta: una finestra TOLTA dal
    -- gestore puo' restare visibile per quanto ne sa lei. Succedeva aprendo la
    -- mappa dal tasto del pannello: il volantino spariva e la cornice restava
    -- aperta e vuota. La seconda domanda e' l'idioma di vanilla, che se la fa
    -- per la stessa ragione (ISWorldMap:onMouseUpPrintMedia).
    local ok, on = pcall(function()
        return self.pm.javaObj:isVisible()
            and UIManager.getUI():contains(self.pm.javaObj)
    end)
    if not ok then return false end
    if on then self.nwSeen = true return true end
    return not self.nwSeen
end

function NW_ReadWindow:onReveal(button)
    local node = button.nwNode
    if not node or not node.onLeftClick then return end
    pcall(function() node:onLeftClick() end)
    -- Svelare porta il giocatore sulla mappa del mondo: mette in coda una
    -- lettura e svuota la coda di quella che teneva aperto il volantino. Il
    -- foglio quindi se ne va da se', e una cornice attorno a niente non ha
    -- ragione di restare. Si chiude qui, subito, invece di aspettare che se ne
    -- accorga il controllo di ogni frame.
    self:onClose()
end

function NW_ReadWindow:onClose()
    if self.nwClosed then return end
    self.nwClosed = true
    -- La trascrizione vive con il foglio che trascrive.
    if NW_Transcript.instance then NW_Transcript.instance:close() end
    pcall(function() UIManager.RemoveElement(self.pm.javaObj) end)
    if NW_ReadWindow.instance == self then NW_ReadWindow.instance = nil end
    self:setVisible(false)
    self:removeFromUIManager()
end

--- Costruisce la cornice attorno a una finestra di lettura appena aperta.
function NW_ReadWindow.wrap(pm, title)
    if not pm then return nil end
    if NW_ReadWindow.instance then NW_ReadWindow.instance:onClose() end

    local w = NW_ReadWindow:new(0, 0, 400, 300)
    w.pm = pm
    w.title = title or ""
    w.baseW, w.baseH = baseSize(pm)
    if not w.baseW then return nil end

    -- La misura di partenza e' quella che la finestra si e' data da se': ci ha
    -- gia' messo dentro il limite dell'80% di schermo in altezza.
    local startW = tonumber(pm.width) or w.baseW
    w.sheetW, w.sheetH = startW, math.floor(w.baseH * startW / w.baseW)

    w:initialise()
    w:instantiate()
    w:addToUIManager()
    -- Il foglio sta SOPRA la cornice, e lo dice lui: cosi' non dipende
    -- dall'ordine in cui le due sono state aggiunte.
    w:setAlwaysOnTop(false)
    pcall(function() pm.javaObj:setAlwaysOnTop(true) end)

    w:fit()
    w:setX(math.floor((getCore():getScreenWidth() - w:getWidth()) / 2))
    w:setY(math.floor((getCore():getScreenHeight() - w:getHeight()) / 2))

    NW_ReadWindow.instance = w
    return w
end

function NW_ReadWindow:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.mapBtns = {}
    o.moveWithMouse = false
    return o
end
