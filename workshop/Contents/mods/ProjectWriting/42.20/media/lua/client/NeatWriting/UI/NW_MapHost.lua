--[[ ============================================================================
    NW_MapHost - una mappa di carta si apre come un nostro foglio.

    LA CATEGORIA CHE MANCAVA. Le mappe stampate e quelle annotate dai
    sopravvissuti sono a tutti gli effetti dei nostri supporti: hanno gia' del
    testo scritto sopra - i simboli e i biglietti che ci ha lasciato chi le ha
    perse - e su quel testo si puo' scrivere, cancellare, disegnare esattamente
    come sulla mappa del mondo. Erano rimaste fuori solo perche' vanilla le apre
    per conto suo, e il risultato era un ibrido: il nostro pannello di scrittura
    accanto alla cornice del gioco, con i suoi tasti sotto.

    Vanilla le infila in un ISCollapsableWindow - barra del titolo, trascinamento,
    ridimensionamento, una fila di tasti in fondo. Qui quella finestra non si usa
    piu': la mappa si apre come una pagina, ferma al centro dello schermo, col
    mondo in pausa e in modalita' lettura, e l'unica cosa attorno e' il pannello
    Writing. Niente da spostare e niente da ridimensionare, perche' non c'e'
    nient'altro da guardare.

    NIENTE MODALITA' WORD, ed e' la stessa ragione della mappa del mondo: il
    testo a righe ha bisogno di una pagina su cui incolonnarsi, e una mappa non
    ce l'ha. Il pannello e' quello della mappa del mondo, identico.

    LA X E LA CHIUSURA. Il pannello chiude chiamando `mapUI.wrap:close()`, che
    e' come chiude quando la finestra di vanilla c'e'. Questo ospite si mette al
    posto di quel wrapper - `map.wrap = self` - e quindi la stessa riga di codice
    funziona in tutti e due i casi senza saperlo.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/Maps/ISMap"
require "NeatWriting/NW_Config"
require "TimedActions/ISReadWorldMap"
require "NeatWriting/NW_Focus"
require "NeatWriting/NW_MapDoc"
require "NeatWriting/NW_Sound"
require "NeatWriting/Patches/NW_Ink"

NW_MapHost = ISPanel:derive("NW_MapHost")

-- Le stesse misure della finestra di scrittura: le due si somigliano perche'
-- sono la stessa cosa vista da due lati.
local GAP    = 16
local MARGIN = 32
local SCRIM  = 0.18
local RINGS  = 10
local RING_A = 0.028

-- ---------------------------------------------------------------------------
-- Costruzione
-- ---------------------------------------------------------------------------

--- La scatola della carta, lasciato il posto a un pannello largo `panelW`.
--- Come su un foglio (NW_Window:pageBox): carta, aria, pannello, tutto il
--- gruppo centrato.
function NW_MapHost:mapBox(panelW)
    local roomW = self.width - panelW - GAP - MARGIN * 2
    local roomH = self.height - MARGIN * 2
    if roomW < 240 then roomW = math.max(240, self.width - MARGIN * 2) end
    local x = math.floor((self.width - (roomW + GAP + panelW)) / 2)
    return x, MARGIN, roomW, roomH
end

--- La carta si stringe per far posto al pannello cresciuto, e il gruppo torna
--- al centro. La chiama il pannello quando si molla la maniglia.
---
--- La mappa si ridimensiona a caldo senza cerimonie: in vanilla sta dentro una
--- finestra che si tira per l'angolo, quindi cambiare misura e' una cosa che
--- sa gia' fare.
function NW_MapHost:refit()
    local map = self.map
    if not map then return end
    local panel = map.nwPanel
    local x, y, w, h = self:mapBox(panel and panel:getWidth() or NW.panelWidth(NW.PANEL_W_WIDE))
    map:setX(x)
    map:setY(y)
    map:setWidth(w)
    map:setHeight(h)
end

function NW_MapHost:createChildren()
    -- Il pannello se lo attacca da se' ISMap:createChildren (NW_Map) come
    -- figlio dell'ospite, ma posizionato OLTRE il bordo destro della mappa -
    -- accanto e non addosso, come sta accanto a un foglio.
    local x, y, roomW, roomH = self:mapBox(NW.panelWidth(NW.PANEL_W_WIDE))

    local map = ISMap:new(x, y, roomW, roomH, self.item, self.playerNum)
    map:initialise()
    -- Ferma: nessuna ancora, perche' non c'e' una finestra che possa cambiare
    -- misura sotto di lei.
    map.anchorLeft, map.anchorRight = false, false
    map.anchorTop, map.anchorBottom = false, false
    map.wrap = self
    self.map = map
    self:addChild(map)
end

-- ---------------------------------------------------------------------------
-- Disegno
-- ---------------------------------------------------------------------------

function NW_MapHost:prerender()
    -- La pausa va riaffermata a ogni frame: il gioco rimette la velocita' da
    -- solo (NW_Focus).
    NW_Focus.hold()
    self:renderDim()
end

--- Lo stesso velo della finestra di scrittura, e per la stessa ragione: a
--- scurire ci pensa la modalita' lettura del gioco, qui resta solo quel poco
--- che stacca la carta dal mondo.
function NW_MapHost:renderDim()
    self:drawRect(0, 0, self.width, self.height, SCRIM, 0, 0, 0)

    local step = math.floor(math.min(self.width, self.height) * 0.04)
    if step < 2 then return end
    for i = 1, RINGS do
        local d = (i - 1) * step
        local w = self.width - d * 2
        local h = self.height - d * 2
        if w <= step * 2 or h <= step * 2 then break end
        local a = RING_A * (RINGS + 1 - i)
        self:drawRect(d, d, w, step, a, 0, 0, 0)
        self:drawRect(d, self.height - d - step, w, step, a, 0, 0, 0)
        self:drawRect(d, d + step, step, h - step * 2, a, 0, 0, 0)
        self:drawRect(self.width - d - step, d + step, step, h - step * 2, a, 0, 0, 0)
    end
end

function NW_MapHost:render() end

-- Il fondo prende i clic che cadono fuori dalla mappa, cosi' non arrivano al
-- mondo dietro: cliccare accanto al foglio non deve far camminare nessuno.
function NW_MapHost:onMouseDown() return true end
function NW_MapHost:onMouseUp() return true end
function NW_MapHost:onRightMouseDown() return true end
function NW_MapHost:onRightMouseUp() return true end

-- ---------------------------------------------------------------------------
-- Aprire e chiudere
-- ---------------------------------------------------------------------------

function NW_MapHost:close()
    if self.nwClosed then return end
    self.nwClosed = true

    if self.keyHandler then
        Events.OnKeyPressed.Remove(self.keyHandler)
        self.keyHandler = nil
    end

    -- Prima si mette via quello che c'e' sulla carta, poi si smonta. I simboli
    -- e i biglietti se ne vanno con la mappa se nessuno li ha copiati, e i
    -- tratti hanno il debito lasciato dal freno da saldare (NW_MapDoc).
    if self.map then
        pcall(function() NW_MapDoc.captureSymbols(self.map, self.player) end)
        pcall(function() NW_Ink.flush(self.map) end)
        pcall(function() self.map:destroy() end)
    end

    if NW_MapHost.instance == self then NW_MapHost.instance = nil end
    -- Una mappa si chiude con il suo rumore, non con quello di un libro.
    NW_Sound.play(self.player, "MapClose")
    NW_Focus.unread(self.player)
    NW_Focus.release()
    self:setVisible(false)
    self:removeFromUIManager()
end

--- Porta il collegamento sulla mappa del mondo.
---
--- SI CHIUDE PRIMA. Svelare vuol dire mettere in coda un'azione a tempo
--- (ISReadWorldMap), e un'azione a tempo parte al primo tick del mondo: noi il
--- mondo lo teniamo fermo, quindi finche' questa finestra e' aperta quel tick
--- non arriva e non succede niente. E' la stessa ragione per cui la modalita'
--- lettura non partiva (lezione 39).
---
--- Le misure si prendono PRIMA di chiudere, perche' chiudendo la mappa muore e
--- con lei la sua API.
function NW_MapHost:toWorldMap()
    local map = self.map
    local player = self.player
    if not map or not map.mapAPI or not player then return end

    local cx, cy, zoom
    local ok = pcall(function()
        local a = map.mapAPI
        cx = (a:getMinXInSquares() + a:getMaxXInSquares()) / 2
        cy = (a:getMinYInSquares() + a:getMaxYInSquares()) / 2
        zoom = a:getZoomF()
    end)
    if not ok or not cx then return end

    self:close()

    pcall(function()
        player:setJoypadIgnoreAimUntilCentered(true)
        ISTimedActionQueue.clear(player)
        ISTimedActionQueue.add(ISReadWorldMap:new(player, cx, cy, zoom))
    end)
end

--- Esc chiude, come su un foglio. La mappa non ha un fuoco di tastiera suo,
--- quindi il tasto passa da un evento globale.
function NW_MapHost:onGlobalKey(key)
    if self.nwClosed then return end
    if key == Keyboard.KEY_ESCAPE then self:close() end
end

--- Apre una mappa di carta. `nil` se non si puo', e allora chi chiama lascia
--- fare a vanilla.
function NW_MapHost.open(item, playerNum)
    local player = getSpecificPlayer(playerNum or 0)
    if not item or not player then return nil end

    if NW_MapHost.instance then NW_MapHost.instance:close() end

    local host = NW_MapHost:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    host.item = item
    host.player = player
    host.playerNum = playerNum or 0
    host.background = false

    host:initialise()
    host:instantiate()
    host:addToUIManager()
    host:setAlwaysOnTop(true)

    -- L'ORDINE E' QUELLO DI VANILLA, e non e' un dettaglio: il deposito si
    -- costruisce DOPO che la mappa esiste. Anticiparlo sembrava piu' logico -
    -- prima i dati, poi chi li legge - ma vanilla lo fa qui, e su come il
    -- motore lega le annotazioni all'oggetto vanilla ha ragione per definizione.
    pcall(function() item:doBuildingStash() end)

    -- E adesso si rimette quello che manca: i simboli e i biglietti che avevamo
    -- messo via alla chiusura e che sulla carta non sono tornati da soli. Dopo
    -- il deposito, non prima, altrimenti non si saprebbe cosa c'e' gia'.
    pcall(function() NW_MapDoc.restoreSymbols(host.map) end)

    pcall(function() player:addReadMap(item) end)

    NW_Focus.take()
    NW_Focus.read(player)
    NW_Sound.play(player, "MapOpen")

    host.keyHandler = function(key) host:onGlobalKey(key) end
    Events.OnKeyPressed.Add(host.keyHandler)

    NW_MapHost.instance = host
    return host
end

function NW_MapHost:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.anchorLeft, o.anchorTop = true, true
    o.anchorRight, o.anchorBottom = true, true
    return o
end
