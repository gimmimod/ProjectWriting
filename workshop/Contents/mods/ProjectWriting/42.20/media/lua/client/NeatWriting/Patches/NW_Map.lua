--[[ ============================================================================
    NW_Map - the Writing panel takes the place of the vanilla symbols panel.

    Vanilla's ISWorldMapSymbols is not removed, it is hidden and kept: it owns
    the symbol catalogue, the annotation store and the multiplayer sync. Ours is
    the face; that one stays the hands.

    Which tools go where:
      symbol, move, rotate    -> vanilla's, driven through symbolsUI
      draw, erase, note, edit -> ours (NW_Ink), because vanilla has no freehand,
                                 its eraser ignores our strokes, and its note and
                                 resize both open dialogs we are replacing.

    The panel is always on screen with the map - no button to find first.

    TUTTO QUESTO SI PUO' SPEGNERE. "Lascia la mappa al gioco" (Opzioni > Mod)
    rimette vanilla al suo posto per intero: i suoi pannelli, i suoi tasti, la
    sua condivisione delle annotazioni. Restano solo i pacchetti di simboli,
    perche' quelli non passano di qui - si registrano in MapSymbolDefinitions e
    il pannello di vanilla li trova da se'. L'ha chiesto chi manda avanti un
    server costruito sulla mappa del gioco, e non e' una resa: e' che meta'
    della mod - scrivere sulla carta - non c'entra niente con la mappa.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/Maps/ISMap"
require "ISUI/Maps/ISWorldMap"
require "ISUI/Maps/ISWorldMapSymbols"
require "NeatWriting/UI/NW_MapHost"
require "NeatWriting/UI/NW_Panel"
require "NeatWriting/NW_Sound"
require "NeatWriting/NW_Undo"
require "NeatWriting/Patches/NW_Ink"
require "NeatWriting/NW_MapDoc"
require "NeatWriting/NW_NetClient"
require "NeatWriting/NW_Share"
require "NeatWriting/NW_Style"
require "NeatWriting/NW_Media"
require "NeatWriting/NW_Follow"
require "NeatWriting/NW_Cartography"
require "NeatWriting/NW_DarkMap"

local PAD = NW.PAD

--- Il nostro spazio in questo file: ci sta la mappa che e' davanti, che serve
--- a Ctrl+Z per sapere su quale disegno tornare indietro.
NW_Map = NW_Map or {}

-- ---------------------------------------------------------------------------
-- Lasciare la mappa al gioco
-- ---------------------------------------------------------------------------
--
-- Ogni sostituzione di questo file passa da qui, e con l'opzione accesa
-- (Opzioni > Mod > Project Writing) restituisce a vanilla il suo lavoro: la
-- mappa torna la sua, con i suoi pannelli, i suoi tasti e la sua condivisione.
--
-- SI CHIEDE OGNI VOLTA, non una volta al caricamento. Un file di patch gira
-- quando il gioco carica il Lua, molto prima che qualcuno possa aver scelto
-- qualcosa: una copia presa li' racconterebbe per sempre com'erano le opzioni
-- alla partenza, e il tasto non farebbe niente fino al riavvio.
--
-- Restano i simboli, perche' non sono di questo file: si registrano in
-- MapSymbolDefinitions (shared/Definitions) e il pannello di vanilla li trova
-- da se'. Era la richiesta esatta - "l'unica cosa che deve rimanere sulla
-- mappa sono i pacchetti" - e viene gratis.
local function theirs()
    return NW.vanillaMap()
end

-- Vanilla outlines whatever the mouse is over through this one function, for
-- all of its tools at once. It is silenced rather than recoloured: NW_Ink draws
-- the selection box for every tool we offer, so leaving this on meant move and
-- rotate got two orange shapes at once - vanilla's tight outline plus our box.
--
-- One box, drawn in one place, is also what keeps move, rotate, resize and
-- erase looking like the same gesture.
ISWorldMapSymbols.renderSymbolOutline_prepatch_neatwriting = ISWorldMapSymbols.renderSymbolOutline
function ISWorldMapSymbols:renderSymbolOutline(symbol, r, g, b)
    if theirs() then
        return self:renderSymbolOutline_prepatch_neatwriting(symbol, r, g, b)
    end
end

-- Vanilla previews the note being typed by reading fields off its own dialog
-- (modal.currentColor:getR(), the font picker, the tickboxes). We never open
-- that dialog, so the preview had nothing to read and threw ten times a second.
-- The field on the map is the preview now.
ISWorldMapSymbolTool_AddNote.render_prepatch_neatwriting = ISWorldMapSymbolTool_AddNote.render
function ISWorldMapSymbolTool_AddNote:render()
    if theirs() then return self:render_prepatch_neatwriting() end
end

-- ---------------------------------------------------------------------------
-- Driving the vanilla symbols panel
-- ---------------------------------------------------------------------------

local TOOL_MAP = {
    symbol = "AddSymbol",
    move   = "MoveAnnotation",
    rotate = "RotateAnnotation",
}

local function symbolsUI(mapUI)
    return mapUI and mapUI.symbolsUI or nil
end

--- Vanilla's AddSymbol reads selectedSymbol.tex without checking, so arming it
--- with nothing chosen throws. Fall back to the first symbol of the sheet.
local function ensureSymbol(sui)
    if sui.selectedSymbol then return true end
    if sui.buttonList then
        for _, b in ipairs(sui.buttonList) do
            if b.tex then sui.selectedSymbol = b return true end
        end
    end
    return false
end

local function tell(text)
    if NW_NetClient and NW_NetClient.verbose then print("NW_Map: " .. text) end
end

local function applyTool(mapUI, id)
    local sui = symbolsUI(mapUI)
    if not (sui and sui.tools) then
        tell("strumento " .. tostring(id) .. ": NIENTE PANNELLO SIMBOLI di vanilla")
        return
    end
    if id == "symbol" and not ensureSymbol(sui) then
        tell("strumento simbolo: NESSUN SIMBOLO SCELTO e la tavola di vanilla e' vuota")
        return
    end
    local name = id and TOOL_MAP[id] or nil
    sui:setCurrentTool(name and sui.tools[name] or nil)
    tell("strumento " .. tostring(id) .. " -> vanilla " .. tostring(name))
end

local function applySymbol(mapUI, sym)
    local sui = symbolsUI(mapUI)
    if not (sui and sui.buttonList and sym) then
        tell("simbolo " .. tostring(sym and sym.id) .. ": niente pannello o niente tavola")
        return
    end
    for _, b in ipairs(sui.buttonList) do
        if b.tex == sym.id then
            sui.selectedSymbol = b
            applyTool(mapUI, "symbol")
            return
        end
    end
    tell("simbolo " .. tostring(sym.id) .. ": NON TROVATO fra i "
        .. tostring(#sui.buttonList) .. " della tavola di vanilla")
end

--- The ink the player picked, handed to vanilla in its own currency.
local function applyInk(mapUI, inkId)
    local sui = symbolsUI(mapUI)
    if not (sui and inkId and ColorInfo) then return end
    local ink = NW.inkById(inkId)
    local ok, colour = pcall(function() return ColorInfo.new(ink.r, ink.g, ink.b, 1) end)
    if ok and colour then
        sui.currentColor = colour
        if sui.updateSymbolColors then pcall(function() sui:updateSymbolColors() end) end
    end
end

-- ---------------------------------------------------------------------------
-- Our tools get the mouse before the map does
-- ---------------------------------------------------------------------------

local function patchInk(class)
    class.onMouseDown_prepatch_neatwriting = class.onMouseDown
    function class:onMouseDown(x, y)
        if theirs() then return self:onMouseDown_prepatch_neatwriting(x, y) end
        NW_Ink.diag(self, "clic")

        -- UN VOLANTINO SOTTO IL CURSORE HA LA PRECEDENZA SULLA PENNA.
        --
        -- Le icone delle stampe trovate e delle mappe dei nascondigli si
        -- accendono col tasto della lettura, e sono bersagli piccoli mostrati
        -- apposta per essere premuti: li' il clic apre il foglio, non scrive.
        --
        -- E il gesto resta di vanilla dal principio alla fine, trascinamento
        -- compreso. Vanilla riconosce il clic COSI':
        --
        --     local wasDragging = self.dragging          -- onMouseUp
        --     if wasDragging and not self.dragMoved and self:onMouseUpPrintMedia()
        --
        -- cioe' chiede al suo trascinamento se il gesto era cominciato sulla
        -- mappa. Noi quel trascinamento lo spegniamo tre righe piu' sotto,
        -- perche' il tasto sinistro e' della penna e non deve spostare la
        -- vista - e spegnendolo togliamo a vanilla l'unico modo che ha di
        -- sapere che quello era un clic. Le icone comparivano, si illuminavano
        -- sotto il mouse, e premerle non apriva niente.
        if self.mouseOverPrintMedia or self.mouseOverStashMap then
            self.nwMediaGesture = true
            return self:onMouseDown_prepatch_neatwriting(x, y)
        end

        if NW_Ink.owns(self) and NW_Ink.onDown(self, x, y) then return true end
        local r = self:onMouseDown_prepatch_neatwriting(x, y)
        -- Vanilla apre qui il suo trascinamento della vista, sul tasto
        -- sinistro. Lo si lascia girare - dentro c'e' anche il passaggio ai
        -- suoi strumenti dei simboli, che ci serve - e poi, SE C'E' UNO
        -- STRUMENTO IN MANO, gli si toglie il trascinamento: il sinistro e' della
        -- penna e la vista si muove col destro. Due significati sullo stesso
        -- pulsante erano quello che lasciava il gesto incastrato.
        --
        -- A MANI VUOTE IL SINISTRO TORNA DI VANILLA. Era una richiesta precisa:
        -- chi posa matita e gomma - ripremendo lo strumento acceso, o finendo le
        -- penne - vuole la mappa come la conosce, trascinata col sinistro. Senza
        -- niente in mano non c'e' niente con cui confondere il gesto, quindi il
        -- motivo per cui lo toglievamo non c'e' piu'.
        if self.nwTool then self.dragging = false end
        return r
    end

    class.onMouseMove_prepatch_neatwriting = class.onMouseMove
    function class:onMouseMove(dx, dy)
        if theirs() then return self:onMouseMove_prepatch_neatwriting(dx, dy) end
        if NW_Ink.panMove(self) then return true end
        if NW_Ink.owns(self) and NW_Ink.onMove(self, self:getMouseX(), self:getMouseY()) then
            return true
        end
        return self:onMouseMove_prepatch_neatwriting(dx, dy)
    end

    class.onMouseUp_prepatch_neatwriting = class.onMouseUp
    function class:onMouseUp(x, y)
        -- Il gesto cominciato su un volantino si chiude dove e' cominciato: da
        -- vanilla, col suo trascinamento ancora acceso.
        if not theirs() and self.nwMediaGesture then
            self.nwMediaGesture = nil
            return self:onMouseUp_prepatch_neatwriting(x, y)
        end
        if not theirs() and NW_Ink.owns(self) and NW_Ink.onUp(self, x, y) then return true end
        return self:onMouseUp_prepatch_neatwriting(x, y)
    end

    -- Il destro: giu' comincia lo spostamento, su lo chiude. Se la vista non si
    -- e' mossa il clic non era nostro e passa a vanilla, che ci tiene il menu
    -- dell'amministratore.
    class.onRightMouseDown_prepatch_neatwriting = class.onRightMouseDown
    function class:onRightMouseDown(x, y)
        if theirs() then
            if self.onRightMouseDown_prepatch_neatwriting then
                return self:onRightMouseDown_prepatch_neatwriting(x, y)
            end
            return true
        end
        NW_Ink.panDown(self, x, y)
        if self.onRightMouseDown_prepatch_neatwriting then
            self:onRightMouseDown_prepatch_neatwriting(x, y)
        end
        return true
    end

    class.onRightMouseUp_prepatch_neatwriting = class.onRightMouseUp
    function class:onRightMouseUp(x, y)
        if not theirs() and NW_Ink.panUp(self) then return true end
        if self.onRightMouseUp_prepatch_neatwriting then
            return self:onRightMouseUp_prepatch_neatwriting(x, y)
        end
        return true
    end

    class.onRightMouseUpOutside_prepatch_neatwriting = class.onRightMouseUpOutside
    function class:onRightMouseUpOutside(x, y)
        if not theirs() then NW_Ink.panUp(self) end
        if self.onRightMouseUpOutside_prepatch_neatwriting then
            return self:onRightMouseUpOutside_prepatch_neatwriting(x, y)
        end
    end

    -- A gesture that starts on the map often ends somewhere else: over our own
    -- panel, or off the window entirely. Without these two the stroke or the
    -- rubber stayed live, ate every later click, and the map stopped panning.
    class.onMouseUpOutside_prepatch_neatwriting = class.onMouseUpOutside
    function class:onMouseUpOutside(x, y)
        if not theirs() then
            -- Un gesto cominciato su un volantino e finito altrove non e' un
            -- clic: si chiude qui, o resterebbe aperto sul clic dopo.
            self.nwMediaGesture = nil
            NW_Ink.cancel(self)
        end
        if self.onMouseUpOutside_prepatch_neatwriting then
            return self:onMouseUpOutside_prepatch_neatwriting(x, y)
        end
    end

    class.onMouseMoveOutside_prepatch_neatwriting = class.onMouseMoveOutside
    function class:onMouseMoveOutside(dx, dy)
        if not theirs() then
            if NW_Ink.panMove(self) then return true end
            NW_Ink.checkStuck(self)
        end
        if self.onMouseMoveOutside_prepatch_neatwriting then
            return self:onMouseMoveOutside_prepatch_neatwriting(dx, dy)
        end
    end

    -- Ink goes in prerender: children (our panel among them) paint between
    -- prerender and render, so ink drawn in render would cover the panel.
    class.prerender_prepatch_neatwriting = class.prerender
    function class:prerender()
        self:prerender_prepatch_neatwriting()
        if theirs() then return end
        NW_Ink.checkStuck(self)
        NW_Ink.render(self)
        -- L'ora del mondo e i simboli appena nati. Solo sulla mappa del mondo:
        -- la notte veste quella, e una carta in mano resta color carta.
        if NW_Ink.isWorldMap(self) then
            NW_DarkMap.watch(self)
            -- La vista che segue il personaggio: costa una domanda per
            -- fotogramma e lavora solo quando lui si e' mosso.
            NW_Follow.tick(self)
        end

        -- La dissolvenza fra giorno e notte, e sta QUI per una ragione precisa:
        -- il velo deve coprire la mappa mentre lo stile cambia, ma non deve
        -- coprire il pannello Writing - che e' un figlio, e i figli si disegnano
        -- fra prerender e render. Dipinto in render, la finestra si sarebbe
        -- oscurata insieme alla mappa e il gesto sarebbe sembrato un guasto.
        local veil = NW_DarkMap.veil()
        if veil > 0 then
            self:drawRect(0, 0, self.width, self.height, veil * 0.92, 0.02, 0.03, 0.06)
        end
    end
end

patchInk(ISMap)
patchInk(ISWorldMap)

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local function mapSurface(mapUI, title, onClose, onWorldMap, beside)
    return {
        word = false, -- linear text needs a page to anchor to; a map has none
        title = title,
        onWorldMap = onWorldMap,
        -- Sulla mappa del mondo il pannello sta nell'angolo destro e cresce
        -- verso sinistra: la maniglia va di la'. Accanto a una mappa di carta
        -- (`beside`) cresce verso destra come accanto a un foglio, e la carta
        -- si stringe per fargli posto (NW_MapHost:refit).
        growLeft = not beside,
        onResized = function()
            local wrap = mapUI.wrap
            if wrap and wrap.refit then wrap:refit() end
        end,
        -- Asked for, not copied: ISWorldMap sets .character AFTER instantiate(),
        -- so a value read here would be nil for the whole session.
        getPlayer = function()
            return mapUI.character or getSpecificPlayer(mapUI.playerNum or 0)
        end,
        -- Quale delle due mappe e'. Domande e non valori, per la stessa ragione
        -- di `getPlayer`: `mapObj` lo mette ISMap nel proprio costruttore, e
        -- leggerlo qui vorrebbe dire fidarsi di un ordine che non e' nostro.
        -- La mappa del mondo non ha un oggetto sotto, una di carta si'.
        isWorld = function() return mapUI.mapObj == nil end,
        getMapUI = function() return mapUI end,
        getMapItem = function() return mapUI.mapObj end,

        -- UNA MAPPA FABBRICATA DA UN GIOCATORE SI RINOMINA, come un foglio.
        --
        -- Le mappe di vanilla no: il loro nome dice quale pezzo di Kentucky
        -- sono, e cambiarlo sarebbe come riscrivere il titolo di un libro
        -- stampato. Le nostre invece nascono con un nome messo da chi le ha
        -- disegnate, e un nome messo da qualcuno e' un nome che si puo'
        -- cambiare - specialmente il primo, che spesso si accetta di fretta.
        --
        -- La matita e il campo esistono gia' nel pannello (NW_Panel:onRename):
        -- qui si accende solo l'interruttore e si dice dove va a finire il nome.
        canRename = NW_Cartography.isOurs(mapUI.mapObj),
        onRename = function(name)
            local item = mapUI.mapObj
            if not (item and name and name ~= "") then return end
            pcall(function() item:setName(name) end)
            if mapUI.nwPanel then mapUI.nwPanel.surface.title = name end
        end,
        onClose = onClose,
        onTool = function(id)
            mapUI.nwTool = id
            applyTool(mapUI, id)   -- no-op for the tools that are ours
        end,
        onInk = function(id, erasing)
            mapUI.nwInkId = id
            applyInk(mapUI, id)
            if erasing then
                mapUI.nwTool = "erase"
                applyTool(mapUI, nil)
            end
        end,
        onWidth = function(v) mapUI.nwWidth = v end,
        onSymbol = function(sym) applySymbol(mapUI, sym) end,
    }
end

--- Attacca il pannello Writing a una mappa.
---
--- `beside` lo mette accanto alla mappa invece che sopra, ed e' anche un
--- cambio di parentela: diventa FRATELLO della mappa dentro l'ospite, non piu'
--- suo figlio.
---
--- Non e' un dettaglio di stile, e' l'unico modo che funziona. Un figlio che
--- sporge oltre il bordo del padre si DISEGNA, ma il mouse non gli arriva: il
--- motore consegna il clic a un figlio solo se il punto cade dentro al padre.
--- Messo fuori e lasciato figlio, il pannello compariva al posto giusto, con i
--- tasti giusti, e non rispondeva a niente - nemmeno alla X. Da fuori sembrava
--- bloccato; era solo irraggiungibile.
---
--- Sulla mappa del mondo la questione non si pone: li' la mappa e' la finestra
--- intera, e "fuori" non esiste.
local function attachPanel(mapUI, title, onClose, width, onWorldMap, beside)
    local panel = NW_Panel:new(0, PAD, mapSurface(mapUI, title, onClose, onWorldMap, beside), width)
    panel:initialise()
    panel:instantiate()
    -- L'ospite si e' gia' messo in `wrap` prima che la mappa costruisse i suoi
    -- figli, quindi si puo' raggiungere da qui.
    local host = beside and mapUI.wrap or nil
    if host and host.addChild then
        host:addChild(panel)
    else
        mapUI:addChild(panel)
    end
    mapUI.nwPanel = panel

    -- Right edge, every frame: the map is resized with the window, and a panel
    -- that only places itself once ends up off-screen (METODO/03 lesson 21).
    -- The vanilla panel is pushed out of sight here too, rather than at build
    -- time: ISMap's own button can turn it back on at any moment.
    local paint = panel.prerender
    panel.prerender = function(self)
        -- L'opzione puo' cambiare con la mappa gia' costruita: qui il pannello
        -- si fa da parte da solo e smette di reprimere quello di vanilla, che
        -- e' l'unica cosa che si puo' disfare senza rifare i figli.
        --
        -- Non c'e' la strada di ritorno, e non serve: un elemento nascosto non
        -- riceve piu' prerender, quindi da qui non si potrebbe comunque
        -- rivedere. A rimettere le cose a posto ci pensa NW_ModOptions,
        -- buttando via la mappa perche' si ricostruisca da capo.
        if theirs() then
            self:setVisible(false)
            return
        end
        if beside then
            -- Fratello della mappa: le coordinate sono quelle dell'ospite, e la
            -- mappa dice dove finisce. Sedici pixel, gli stessi che stanno fra
            -- la carta e il pannello su un foglio.
            --
            -- Fermo al bordo dello schermo mentre si tira la maniglia: la
            -- mappa si stringe solo quando la si molla (NW_MapHost:refit), e
            -- nel frattempo il pannello che cresce si porterebbe fuori la
            -- maniglia - da dove non si torna indietro.
            local x = mapUI:getX() + mapUI:getWidth() + 16
            local right = getCore():getScreenWidth() - 32 - self:getWidth()
            if x > right then x = math.max(16, right) end
            self:setX(x)
            self:setY(mapUI:getY())
        else
            self:setX(mapUI:getWidth() - self:getWidth() - PAD)
        end
        self.maxHeight = mapUI:getHeight() - PAD * 2
        local sui = symbolsUI(mapUI)
        if sui and sui:isVisible() then sui:setVisible(false) end
        -- Quale mappa e' davanti: il pannello e' l'unica cosa che lo sappia con
        -- certezza, perche' e' disegnato solo con la sua mappa. Serve a Ctrl+Z,
        -- che arriva da un evento globale e non da un elemento.
        NW_Map.active = mapUI
        paint(self)
    end
    return panel
end

-- ---------------------------------------------------------------------------
-- La scelta di condivisione, su quello che posa vanilla
-- ---------------------------------------------------------------------------
--
-- I simboli li posa lo strumento del gioco (`AddSymbol`, pilotato da noi
-- attraverso `setCurrentTool`), quindi la scelta di condivisione va messa
-- addosso al simbolo appena quello ha finito. I biglietti di testo invece sono
-- nostri e se la mettono da soli, in NW_Ink.
--
-- L'aggancio e' quello di RememberMapSharing: si segna quanti simboli c'erano
-- prima, si lascia fare a vanilla, e si vestono quelli comparsi dopo. Non c'e'
-- un evento "e' nato un simbolo" da ascoltare.
local addSymbol = ISWorldMapSymbolTool_AddSymbol.addSymbol
function ISWorldMapSymbolTool_AddSymbol:addSymbol(x, y)
    local sapi = self.symbolsAPI
    local mapUI = self.symbolsUI and self.symbolsUI.mapUI

    -- SENZA PENNA NON SI POSA NIENTE, nemmeno con lo strumento di vanilla. Noi lo
    -- armiamo da fuori, saltando il controllo sugli oggetti che il suo pannello
    -- farebbe prima di lasciarlo usare: la domanda la rifacciamo qui, con la
    -- risposta del nostro pannello (NW_Panel toglie l'inchiostro quando la
    -- borsa resta senza penne).
    if not theirs() and mapUI and not mapUI.nwInkId then return end

    local before = 0
    if sapi then pcall(function() before = sapi:getSymbolCount() end) end

    addSymbol(self, x, y)

    if theirs() or not sapi then return end
    local player = self.symbolsUI and self.symbolsUI.character
    pcall(function()
        for i = before, sapi:getSymbolCount() - 1 do
            local sym = sapi:getSymbolByIndex(i)
            -- Vanilla lo posa sempre a ISMap.SCALE e in piedi: gli si danno la
            -- misura dell'ultimo simbolo ridimensionato e la prospettiva scelta.
            NW_Ink.dressMark(mapUI, sym, "sym")
            -- E l'angolo scelto con Shift + rotella mentre lo si teneva in mano.
            if NW_Placing then NW_Placing.applyAngle(sym) end
            if player then NW_Share.applyTo(sym, player) end
            -- E si annuncia DOPO averlo vestito, o in rete gli altri lo vedono
            -- alla misura di vanilla.
            if sapi.sendModifySymbol then sapi:sendModifySymbol(sym) end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Aprire la mappa del mondo: chiedere quello che gli altri hanno disegnato
-- ---------------------------------------------------------------------------
--
-- Alla richiesta, non alla costruzione: la mappa del mondo si costruisce una
-- volta per partita e si riusa (e' la stessa ragione della lezione 53), mentre
-- quello che gli altri disegnano cambia mentre si gioca. Ogni apertura chiede,
-- e la risposta arriva a blocchi da NW_NetClient.
--- Butta la mappa del mondo costruita, perche' la prossima apertura la rifaccia.
---
--- ISWorldMap.ShowWorldMap tiene l'istanza in una globale e la ricostruisce solo
--- tornando al menu principale: i suoi figli sono vestiti o spogli come erano la
--- prima volta che si e' aperta. Buttarla e' quello che fa vanilla stessa
--- uscendo al menu. Il prezzo e' la vista corrente, che si riapre centrata sul
--- personaggio.
function NW_Map.dropWorldMap()
    local wm = rawget(_G, "ISWorldMap_instance")
    if not wm then return end
    pcall(function()
        if wm:isVisible() then ISWorldMap.HideWorldMap(wm.playerNum or 0) end
    end)
    pcall(function() wm:removeFromUIManager() end)
    _G.ISWorldMap_instance = nil
    if ISWorldMap then ISWorldMap.instance = nil end
end

-- ---------------------------------------------------------------------------
-- I biglietti col "%" si riparano FUORI dal disegno
-- ---------------------------------------------------------------------------
--
-- LA MAPPA RESTAVA BIANCA, SENZA UN ERRORE. Un biglietto salvato come chiave
-- con un "%" dentro (NW_MapDoc.repairNotes) non rompe solo il clic: il motore
-- lo passa al traduttore anche mentre impagina e disegna i simboli, dentro
-- UIWorldMap.render - che disegna la mappa PRIMA di chiamare il prerender Lua
-- (letto nel bytecode). L'eccezione salta fuori li', il resto del fotogramma
-- non viene mai disegnato - restano il fondo color carta e nient'altro - e il
-- nostro prerender, dove stava la riparazione, non arriva mai. Nel log non
-- resta niente, perche' a fallire e' proprio la riga che doveva scriverlo.
--
-- Quindi si ripara da dove il disegno della mappa non c'entra: all'apertura,
-- subito dopo che vanilla l'ha costruita, e a ogni fotogramma prima che
-- l'interfaccia si disegni (OnPreUIDraw) - per la mappa del mondo e per la
-- minimappa, che mostra gli stessi simboli. Le mappe di carta dal loro update.
-- Il controllo e' un conteggio: non costa niente finche' nessuno aggiunge note.
-- Anche con la mappa lasciata al gioco: quei biglietti li hanno scritti le
-- versioni precedenti di questa mod, e rompono anche la mappa di vanilla.
local function repairWorldNotes()
    local wm = rawget(_G, "ISWorldMap_instance")
    local sui = wm and wm.symbolsUI
    if sui then NW_MapDoc.repairNotes(wm, sui.symbolsAPI) end
    if not getPlayerMiniMap then return end
    for i = 0, getNumActivePlayers() - 1 do
        local mini = getPlayerMiniMap(i)
        local inner = mini and mini.inner
        if inner and inner.mapAPI then
            local sapi
            pcall(function() sapi = inner.mapAPI:getSymbolsAPIv2() end)
            NW_MapDoc.repairNotes(inner, sapi)
        end
    end
end

Events.OnPreUIDraw.Add(function() pcall(repairWorldNotes) end)

if ISMap.update then
    local mapUpdate = ISMap.update
    function ISMap:update(...)
        pcall(function()
            local sui = self.symbolsUI
            NW_MapDoc.repairNotes(self, sui and sui.symbolsAPI)
        end)
        return mapUpdate(self, ...)
    end
end

local showWorldMap = ISWorldMap.ShowWorldMap
ISWorldMap.ShowWorldMap = function(playerNum, centerX, centerY, zoom)
    -- LA MAPPA VESTITA COME LA VUOLE LA PARTITA ADESSO. L'opzione del giocatore
    -- butta la mappa appena la si cambia (NW_ModOptions), ma quella sandbox la
    -- cambia un admin, dal server, a partita avviata: nessuno qui se ne accorge
    -- nel momento in cui succede. Ci se ne accorge aprendo - la mappa ricorda
    -- con quale regola e' stata costruita, e se non e' piu' quella si rifa'.
    pcall(function()
        local wm = rawget(_G, "ISWorldMap_instance")
        if wm and wm.nwBuiltVanilla ~= nil and wm.nwBuiltVanilla ~= theirs() then
            NW_Map.dropWorldMap()
        end
    end)
    showWorldMap(playerNum, centerX, centerY, zoom)
    -- Prima del primo fotogramma della mappa appena costruita o riaperta.
    pcall(repairWorldNotes)
    if theirs() then return end
    pcall(function() NW_NetClient.requestSync() end)
    -- La notte, se era accesa quando si e' chiusa. Senza dissolvenza: non c'e'
    -- niente da cui dissolvere, la mappa si apre gia' com'era.
    pcall(function()
        local ui = ISWorldMap_instance
        if ui then NW_DarkMap.restore(ui) end
    end)
    pcall(function() NW_Ink.diag(ISWorldMap_instance, "apertura") end)
    -- La vista che segue il personaggio, se l'elicottero e' acceso.
    pcall(function() NW_Follow.onOpen(ISWorldMap_instance) end)
    -- Se vanilla ha fermato il gioco aprendo la mappa, lo si ricorda: la
    -- chiusura di vanilla lo fa ripartire solo se "deve mettere in pausa" dice
    -- ancora si', e con la nostra opzione accesa nel frattempo direbbe no -
    -- lasciando il gioco fermo a mappa chiusa. Si chiede a shouldPause, non alla
    -- velocita': un gioco gia' messo in pausa a mano prima di aprire non e'
    -- una pausa della mappa, e chiudendo non va fatto ripartire.
    pcall(function() ISWorldMap_instance.nwPausedOnOpen = ISWorldMap.shouldPause() == true end)
    -- I volantini letti: in rete il gioco se li dimentica fra una sessione e
    -- l'altra, e senza quelli la mappa non ha icone da mostrare (NW_Media).
    pcall(function() NW_Media.sync(getSpecificPlayer(playerNum or 0)) end)
    -- I simboli travasati da una mappa trovata aspettano qui il loro momento:
    -- l'archivio in cui devono entrare e' quello della finestra della mappa del
    -- mondo, e quando si legge il foglio quella finestra puo' non esistere.
    -- Adesso esiste.
    pcall(function()
        local ui = ISWorldMap_instance
        if ui then
            NW_Cartography.drainPending(ui, getSpecificPlayer(playerNum or 0))
        end
    end)
end

-- ---------------------------------------------------------------------------
-- La mappa satellitare rifa lo stile, e si porta via la notte
-- ---------------------------------------------------------------------------
--
-- onToggleTerrainImage ricostruisce lo stile da zero tutte e due le volte, e
-- il nostro strato scuro sparisce con tutto il resto: la mappa tornava chiara
-- mentre il tasto delle impostazioni continuava a mostrare la luna. Si rimette
-- subito dopo, senza dissolvenza - il cambio di mappa e gia una transizione
-- sua, e sovrapporne una seconda le darebbe uno scatto.
local toggleTerrain = ISWorldMap.onToggleTerrainImage
if toggleTerrain then
    function ISWorldMap:onToggleTerrainImage()
        toggleTerrain(self)
        if theirs() then return end
        pcall(function() NW_DarkMap.apply(self) end)
    end
end

-- ---------------------------------------------------------------------------
-- Ctrl+Z on the map
-- ---------------------------------------------------------------------------
--
-- The map has no keyboard handling of its own - vanilla's map is all mouse - so
-- this is a global listener, filtered down to the one map that is on screen.
-- It only ever takes back our freehand strokes: symbols and notes belong to
-- vanilla's annotation store, which has no step back of its own.

local function ctrlDown()
    return Keyboard.isKeyDown(Keyboard.KEY_LCONTROL)
        or Keyboard.isKeyDown(Keyboard.KEY_RCONTROL)
end

local function onMapKey(key)
    if key ~= Keyboard.KEY_Z or not ctrlDown() then return end
    local mapUI = NW_Map.active
    if not mapUI or not mapUI.nwPanel then return end
    if not mapUI:isVisible() then NW_Map.active = nil return end
    if NW_Undo.undo(mapUI) then
        NW_Ink.save(mapUI, true)
        NW_Sound.erase(NW_Ink.playerOf(mapUI))
    end
end
Events.OnKeyPressed.Add(onMapKey)

-- ---------------------------------------------------------------------------
-- Closing: what the brake put off has no later left
-- ---------------------------------------------------------------------------
--
-- Freehand strokes are written to the map's memory a second at a time, so that
-- a long erase drag does not rewrite the store at every pixel. Closing the map
-- is the one moment when "in a second" is too late, so both doors flush first.

ISMapWrapper.close_prepatch_neatwriting = ISMapWrapper.close
function ISMapWrapper:close()
    pcall(function() NW_Ink.flush(self.mapUI) end)
    if NW_Map.active == self.mapUI then NW_Map.active = nil end
    self:close_prepatch_neatwriting()
end

ISWorldMap.close_prepatch_neatwriting = ISWorldMap.close
function ISWorldMap:close()
    pcall(function() NW_Ink.flush(self) end)
    -- E i simboli tornano del loro colore. Di notte quello scritto dentro e' il
    -- nostro, ed e' quello che una partita salvata a mappa chiusa porterebbe via
    -- credendolo il colore scelto da chi ha scritto.
    pcall(function() NW_DarkMap.untint(self) end)
    if NW_Map.active == self then NW_Map.active = nil end
    local paused = self.nwPausedOnOpen
    self.nwPausedOnOpen = nil
    self:close_prepatch_neatwriting()
    -- La meta' di vanilla che si sarebbe persa: vedi l'apertura.
    if paused and not isClient() then
        pcall(function() if getGameSpeed() == 0 then setGameSpeed(1) end end)
    end
end

-- ---------------------------------------------------------------------------
-- The paper map (ISMap)
-- ---------------------------------------------------------------------------

-- I tasti di vanilla se ne vanno TUTTI.
--
-- Una mappa di carta deve avere l'interfaccia di un nostro foglio, e un foglio
-- non ha una fila di tasti sotto: ha il pannello Writing e nient'altro. Una fila
-- vestita da noi resta una fila in piu', e una carta con due interfacce
-- addosso e' esattamente quello che si voleva togliere.
--
--   CHIUDI            la X rossa del pannello, e Esc
--   MODIFICA SIMBOLI  il pannello di vanilla, che noi sostituiamo
--   POSA SIMBOLO      esiste solo per il controller
--   SCALA             la rotella ingrandisce, il destro sposta
--   MAPPA DEL MONDO   diventa l'unico tasto in piu' nell'header del pannello
--
-- Ci rimette la legenda, che sulla mappa di carta non ha piu' un tasto suo.
local DROP = {
    "ok", "editSymbolsBtn", "placeSymbBtn", "scaleBtn", "showMapKey", "revealBtn",
}

local function dressPaperMapButtons(mapUI)
    for _, name in ipairs(DROP) do
        local b = mapUI[name]
        if b then
            b:setVisible(false)
            b:setWidth(0)
            b:setX(-1000)
        end
    end
end

--- Il collegamento alla mappa del mondo, se questa mappa e' aperta da noi.
---
--- Solo allora: quando si apre nella finestra di vanilla - il ripiego, se il
--- nostro ospite non nasce - il wrapper e' un ISCollapsableWindow che quel gesto
--- non ce l'ha, e un tasto che non fa niente e' peggio di un tasto che manca.
--- La distinzione si fa da se': il nostro ospite si mette in `wrap` PRIMA che la
--- mappa costruisca i suoi figli, vanilla dopo.
local function worldMapLink(mapUI)
    local wrap = mapUI.wrap
    if not wrap or not wrap.toWorldMap then return nil end
    return function() wrap:toWorldMap() end
end

ISMap.createChildren_prepatch_neatwriting = ISMap.createChildren
function ISMap:createChildren()
    self:createChildren_prepatch_neatwriting()
    if theirs() then return end

    -- getName esiste su ogni oggetto dell'inventario: chiederselo prima era una
    -- cautela di troppo, e il pcall copre gia' il caso in cui la chiamata vada
    -- storta per altro.
    local name = nil
    if self.mapObj then pcall(function() name = self.mapObj:getName() end) end
    local link = worldMapLink(self)
    attachPanel(self, name or getText("IGUI_NW_SubjectMap"), function()
        -- Closes the map, not just the panel: with the panel always on screen,
        -- closing only it would leave a map you cannot annotate and no way back.
        if self.wrap and self.wrap.close then
            self.wrap:close()
        elseif self.close then
            self:close()
        end
    end, NW.PANEL_W_WIDE, link, link ~= nil)

    dressPaperMapButtons(self)
end

-- ---------------------------------------------------------------------------
-- Aprire una mappa di carta
-- ---------------------------------------------------------------------------
--
-- Vanilla la infila in un ISCollapsableWindow: barra del titolo, trascinamento,
-- angolo per ridimensionare, e una fila di tasti suoi in fondo. Accanto al
-- nostro pannello era un ibrido - meta' cornice del gioco e meta' nostra - e la
-- mappa annotata da un sopravvissuto e' a tutti gli effetti uno dei nostri
-- supporti: ha gia' del testo sopra e ci si scrive allo stesso modo.
--
-- Adesso si apre come una pagina: ferma, al centro, mondo in pausa. Se per
-- qualunque ragione l'ospite non si apre, si torna a vanilla senza dire niente:
-- meglio la finestra del gioco che nessuna mappa.
local openMap = ISInventoryPaneContextMenu.onCheckMap
ISInventoryPaneContextMenu.onCheckMap = function(map, player)
    local playerObj = getSpecificPlayer(player)
    if playerObj and map and not theirs() then
        -- La mappa va prima presa in mano, come fa vanilla: e' la stessa
        -- ragione per cui esiste quel controllo, e saltarlo vorrebbe dire
        -- leggere una mappa dall'altra parte della stanza.
        -- Si controlla che ci sia invece di fidarsi: in Kahlua chiamare un nil
        -- e' un'eccezione Java che il pcall non ferma (lezione 33), e qui
        -- costerebbe al giocatore la mappa.
        local away = false
        if luautils and luautils.haveToBeTransfered then
            away = luautils.haveToBeTransfered(playerObj, map)
        end
        if not away then
            local ok, host = pcall(NW_MapHost.open, map, player)
            if ok and host then return end
            if not ok then print("NW_Map: " .. tostring(host)) end
        end
    end
    return openMap(map, player)
end

-- ---------------------------------------------------------------------------
-- The world map (ISWorldMap)
-- ---------------------------------------------------------------------------

ISWorldMap.createChildren_prepatch_neatwriting = ISWorldMap.createChildren
function ISWorldMap:createChildren()
    self:createChildren_prepatch_neatwriting()
    -- Con quale regola e' nata: ShowWorldMap la confronta a ogni apertura.
    self.nwBuiltVanilla = theirs()
    if theirs() then return end
    attachPanel(self, getText("IGUI_NW_SubjectWorldMap"), function()
        ISWorldMap.HideWorldMap(self.playerNum or 0)
    end, NW.PANEL_W_WIDE)
end
