--[[ ============================================================================
    NW_Cartography - ritagliare un pezzo di mondo e farne un oggetto.

    Due mappe fabbricate, un meccanismo solo:

      NW_AnnotatedMap  un rettangolo che hai inquadrato sulla mappa del mondo,
                       coi segni che ci stavano dentro. Costa un foglio e
                       qualcosa per scrivere.

    IL VISORE NON L'HO SCRITTO IO, ed e' il motivo per cui questo file e' corto.
    Sono oggetti mappa veri (`ItemType = base:map`), quindi il gioco li apre con
    la sua finestra; il pannello Writing ci si aggancia come su qualunque mappa
    di carta; e i segni li mette gia' NW_MapDoc, che sa leggere e riscrivere sia
    i nostri tratti (`NeatWriting.ink`) sia i simboli di vanilla
    (`NeatWriting.sym`). Qui dentro restano tre cose che nessun altro fa:

      1. tagliare la vista sull'area giusta      -> LootMaps.Init
      2. riempire l'oggetto al momento in cui nasce
      3. travasare i segni sulla mappa di chi legge, se lo chiede

    IL RITAGLIO E' LA RICETTA DI MarchRidgeMap, guardata e copiata: si caricano
    i dati del mondo intero e poi si stringe la vista con `setBoundsInSquares`.
    Un solo MapID per infinite mappe diverse - i confini stanno nella modData
    dell'OGGETTO, non nello script - perche' `LootMaps.Init` e' indicizzato sul
    MapID e un MapID per mappa vorrebbe dire un item script per mappa.

    IL TRAVASO SI CHIEDE. La mappa svela da se' il rettangolo che rappresenta -
    e' quello che fa una mappa di carta anche in vanilla, letta la si conosce -
    ma i SEGNI no: aprire una mappa trovata per terra e ritrovarsi duecento
    annotazioni altrui addosso, senza un modo per tornare indietro, e' un regalo
    che nessuno ha chiesto. Un tasto, una domanda, e poi si travasa.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Tools"
require "NeatWriting/NW_NetClient"
require "NeatWriting/NW_MapDoc"
require "NeatWriting/NW_PlayerStore"
require "NeatWriting/NW_Net"
require "NeatWriting/NW_DarkMap"

NW_Cartography = NW_Cartography or {}
local C = NW_Cartography

--- I due oggetti, con il nome esatto con cui li dichiara
--- `media/scripts/items_neatwriting.txt`. La marca `--@oggetti` li fa
--- confrontare con quel file da `oggetti.js`: si fabbricano con
--- `instanceItem("Base." .. C.ANNOTATED)`, quindi uno scarto fra qui e li'
--- darebbe un `instanceItem` che risponde nil, e nessun errore da nessuna
--- parte - il tasto premuto e niente in mano.
C.ANNOTATED = "NW_AnnotatedMap"  --@oggetti

--- Il tetto al carico di una mappa, in caratteri di punti.
---
--- La modData di un oggetto viaggia in rete insieme all'oggetto, e un oggetto
--- non e' un posto dove mettere mezzo megabyte: il limite duro sugli oggetti
--- giocatore e' 2 MB (misurato con peso-tratti.js), e una mappa e' una cosa che
--- si passa di mano, si mette in una cassa, si porta addosso in dieci copie.
--- Il tetto e' volutamente molto piu' basso di quanto reggerebbe: una mappa
--- annotata e' un appunto su una zona, non l'archivio di una campagna.
C.MAX_STROKE_CHARS = 120000
C.MAX_SYMBOLS = 400

-- ---------------------------------------------------------------------------
-- I confini, scritti sull'oggetto
-- ---------------------------------------------------------------------------

local function modDataOf(item)
    local md
    pcall(function() md = item:getModData() end)
    return md
end

--- Il rettangolo che questa mappa rappresenta, o nil se l'oggetto non lo dice.
function C.bounds(item)
    if not item then return nil end
    local md = modDataOf(item)
    local d = md and md.NeatWriting
    local c = d and d.crop
    if type(c) ~= "table" then return nil end
    local x1, y1 = tonumber(c.x1), tonumber(c.y1)
    local x2, y2 = tonumber(c.x2), tonumber(c.y2)
    if not (x1 and y1 and x2 and y2) then return nil end
    if x2 <= x1 or y2 <= y1 then return nil end
    return x1, y1, x2, y2
end

--- Chi l'ha disegnata. Serve al titolo e al tooltip, non ai permessi.
function C.author(item)
    local md = modDataOf(item)
    local d = md and md.NeatWriting
    return d and d.mapAuthor or nil
end

-- ---------------------------------------------------------------------------
-- Il taglio della vista
-- ---------------------------------------------------------------------------

--- La stessa sequenza di MarchRidgeMap, meno `replaceWaterStyle`, che e' una
--- locale di ISMapDefinitions e da fuori non si chiama. E' solo il colore
--- dell'acqua.
local function initCropped(mapUI)
    local mapAPI
    pcall(function() mapAPI = mapUI.javaObject:getAPIv1() end)
    if not mapAPI then return end

    pcall(function()
        MapUtils.initDirectoryMapData(mapUI, LootMaps.DEFAULT_MAP_DIRECTORY)
        MapUtils.initDefaultStyleV3(mapUI)
    end)

    local x1, y1, x2, y2 = C.bounds(mapUI.mapObj)
    local ok = false
    if x1 then
        ok = pcall(function() mapAPI:setBoundsInSquares(x1, y1, x2, y2) end)
    end

    -- IL RITAGLIO ERA MUTO, e da fuori "la mappa si apre sul mondo intero" ha
    -- tre cause che si somigliano: l'oggetto non porta i confini, i confini ci
    -- sono e non si leggono, oppure si leggono e `setBoundsInSquares` non li
    -- accetta. Questa riga le distingue.
    if NW_NetClient and NW_NetClient.verbose then
        if not x1 then
            print("NW_Cartography: ritaglio SENZA confini sull'oggetto, si apre il mondo intero")
        else
            print("NW_Cartography: ritaglio " .. x1 .. "," .. y1 .. " -> " .. x2 .. "," .. y2
                .. (ok and " applicato" or " RIFIUTATO da setBoundsInSquares"))
        end
    end

    pcall(function() MapUtils.overlayPaper(mapUI) end)
end

--- Le due voci che il gioco cerca quando apre uno dei nostri oggetti.
---
--- Si registrano a OnGameStart e non al caricamento del file: `LootMaps` nasce
--- in ISMapDefinitions, che e' di vanilla e non promette di essere gia' passato
--- quando passiamo noi. Scrivere dentro una tabella che non esiste ancora
--- creerebbe una globale nuova, e la mappa si aprirebbe sul mondo intero senza
--- che nessuno dica niente.
local function register()
    if not LootMaps or not LootMaps.Init then return end
    LootMaps.Init[C.ANNOTATED] = initCropped
end

Events.OnGameStart.Add(register)
Events.OnGameBoot.Add(register)

-- ---------------------------------------------------------------------------
-- Cosa sta dentro il rettangolo
-- ---------------------------------------------------------------------------

local function inside(x, y, x1, y1, x2, y2)
    return x and y and x >= x1 and x <= x2 and y >= y1 and y <= y2
end


--- Il testo mostrato da un biglietto, comunque sia stato messo, senza mai
--- passare un "%" al traduttore: la stessa lettura di NW_MapDoc, che e' l'altro
--- posto che li salva (li' il perche', col bytecode di WorldMapTextSymbol).
local function textOf(s)
    return NW_MapDoc.noteText(s)
end

--- La firma con cui due simboli sono "lo stesso": che tipo, quale, e dove.
---
--- E' la stessa di NW_MapDoc.symKey, e deve restare la stessa: sono i due posti
--- che rimettono simboli su una mappa, e se non fossero d'accordo su cosa
--- significa "uguale" uno dei due ridarebbe indietro i doppioni dell'altro.
--- Le coordinate si arrotondano al quadrato, perche' un simbolo posato a mano
--- non torna mai allo stesso millesimo.
local function symKey(e)
    return (e.t or "?") .. "|" .. tostring(e.id) .. "|"
        .. math.floor((e.x or 0) + 0.5) .. "|" .. math.floor((e.y or 0) + 0.5)
end

--- I tratti che cadono, anche solo in parte, dentro il rettangolo.
---
--- Basta un punto: un tratto che entra e riesce e' un tratto che dice qualcosa
--- di quell'area, e tagliarlo a meta' sul bordo lascerebbe monconi che da
--- dentro non si capiscono. Viaggia intero e sborda, come su un foglio.
local function strokesIn(list, x1, y1, x2, y2)
    local out, chars = {}, 0
    for _, s in ipairs(list or {}) do
        local pts = s.pts or s.p
        if type(pts) == "table" and #pts >= 4 then
            local touches = false
            for i = 1, #pts - 1, 2 do
                if inside(pts[i], pts[i + 1], x1, y1, x2, y2) then touches = true break end
            end
            if touches then
                chars = chars + #pts * 8
                if chars > C.MAX_STROKE_CHARS then break end
                out[#out + 1] = { w = s.w or 3.0, c = s.c or "black", p = pts }
            end
        end
    end
    return out, chars
end

--- I simboli di vanilla che cadono dentro il rettangolo, gia' nella forma che
--- NW_MapDoc sa rimettere a posto.
local function symbolsIn(mapUI, x1, y1, x2, y2)
    local out = {}
    local sapi
    pcall(function() sapi = mapUI.symbolsUI and mapUI.symbolsUI.symbolsAPI end)
    if not sapi then return out end

    pcall(function()
        for i = 1, sapi:getSymbolCount() do
            if #out >= C.MAX_SYMBOLS then break end
            local s = sapi:getSymbolByIndex(i - 1)
            local e = {}
            local ok = pcall(function()
                e.x, e.y = s:getWorldX(), s:getWorldY()
                -- Il colore VERO, non quello che ha addosso: di notte i simboli
                -- portano il nostro schiarito, e una mappa ricopiata al buio si
                -- sarebbe portata dietro i colori della notte per sempre.
                e.r, e.g, e.b = NW_DarkMap.trueColor(mapUI,
                    s:getRed(), s:getGreen(), s:getBlue())
                e.a = s:getAlpha()
                e.s = s:getScale()
                e.ax, e.ay = s:getAnchorX(), s:getAnchorY()
                e.rot = s:getRotation()
                if s:isText() then
                    e.t, e.id = "txt", textOf(s)
                else
                    e.t, e.id = "tex", s:getSymbolID()
                end
            end)
            if ok and e.t and e.id ~= nil and inside(e.x, e.y, x1, y1, x2, y2) then
                out[#out + 1] = e
            end
        end
    end)
    return out
end

--- Quanto c'e' dentro quel rettangolo, senza fabbricare niente. Serve al
--- riquadro di inquadratura per dire "qui non c'e' niente" prima di far
--- spendere un foglio.
function C.survey(mapUI, player, x1, y1, x2, y2)
    local strokes = strokesIn(NW_MapDoc.strokes(mapUI, player), x1, y1, x2, y2)
    local symbols = symbolsIn(mapUI, x1, y1, x2, y2)
    return #strokes, #symbols
end

-- ---------------------------------------------------------------------------
-- Fabbricare
-- ---------------------------------------------------------------------------

local function nameOf(player)
    local name
    pcall(function() name = player:getUsername() end)
    if name and name ~= "" and name ~= "nil" then return name end
    -- Da soli non c'e' un nome utente: si usa quello del personaggio, che e'
    -- l'unico nome che il giocatore riconosce come suo.
    pcall(function() name = player:getDescriptor():getForename() end)
    if name and name ~= "" then return name end
    return "?"
end

C.nameOf = nameOf

--- Riempie un oggetto mappa con quello che sta nel rettangolo.
---
--- Scrive nella modData con le stesse chiavi che NW_MapDoc legge, e non con
--- chiavi nostre: cosi' l'oggetto si apre e si annota come qualunque altra
--- mappa di carta, e quello che ci si disegna sopra dopo resta.
function C.fill(item, player, x1, y1, x2, y2, strokes, symbols)
    local md = modDataOf(item)
    if not md then return false end
    local d = md.NeatWriting
    if not d then
        d = { v = NW_MapDoc.VERSION }
        md.NeatWriting = d
    end
    d.crop = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
    d.mapAuthor = nameOf(player)
    d.ink = #strokes > 0 and strokes or nil
    d.sym = #symbols > 0 and symbols or nil
    return true
end

--- La mappa annotata: costa un foglio e qualcosa per scrivere.
---
--- Il foglio si consuma DOPO che l'oggetto e' nato, non prima: se la creazione
--- fallisce a meta' - modData che non risponde, inventario che non accetta -
--- si e' persa la carta e non si e' avuto niente in cambio.
function C.makeAnnotated(mapUI, player, x1, y1, x2, y2, title)
    if not (mapUI and player) then return nil end
    if not NW_Tools.canWrite(player) then return nil, "nopen" end
    local paper = NW_Tools.findPaper(player)
    if not paper then return nil, "nopaper" end

    local strokes = strokesIn(NW_MapDoc.strokes(mapUI, player), x1, y1, x2, y2)
    local symbols = symbolsIn(mapUI, x1, y1, x2, y2)
    if #strokes == 0 and #symbols == 0 then return nil, "empty" end

    local named = title
    if not named or named == "" then
        named = getText("IGUI_NW_MapOf", nameOf(player))
    end

    -- IN RETE LA FABBRICA E' DEL SERVER. Il client manda i confini, i segni e
    -- l'identificativo del foglio da consumare; il server fabbrica, riempie,
    -- consegna e toglie la carta. Cosi' l'oggetto esiste per tutti e resta nel
    -- cadavere, che e' esattamente quello che prima non succedeva.
    if isClient() then
        local paperId
        pcall(function() paperId = paper:getID() end)
        local ok = NW_NetClient.makeMap(player, C.ANNOTATED, x1, y1, x2, y2,
            named, strokes, symbols, nil, paperId)
        if not ok then return nil, "noitem" end
        -- Non si torna un oggetto: quello lo consegnera' il server. Il vero
        -- basta a chi chiama per sapere che la richiesta e' partita.
        return true
    end

    local item
    pcall(function() item = instanceItem("Base." .. C.ANNOTATED) end)
    if not item then return nil, "noitem" end

    if not C.fill(item, player, x1, y1, x2, y2, strokes, symbols) then
        return nil, "noitem"
    end

    pcall(function() item:setName(named) end)

    local inv
    pcall(function() inv = player:getInventory() end)
    if not inv then return nil, "noitem" end
    pcall(function() inv:AddItem(item) end)

    -- DA SOLI SI FABBRICA QUI, e va bene: non c'e' un server con cui non essere
    -- d'accordo, le due meta' sono la stessa macchina virtuale. In rete si passa
    -- di la' (sopra), perche' un oggetto nato con `instanceItem` sul client il
    -- server non l'ha mai visto.
    --
    -- Il foglio si consuma per ULTIMO, quando la mappa esiste gia': se qualcosa
    -- fosse andato storto prima si sarebbe persa la carta senza avere niente in
    -- cambio.
    pcall(function() paper:getContainer():Remove(paper) end)
    return item
end

-- ---------------------------------------------------------------------------
-- Travasare
-- ---------------------------------------------------------------------------

--- Svela il rettangolo sulla mappa di chi legge.
---
--- E' quello che fa una mappa di carta anche in vanilla: letta, quell'area si
--- conosce. In rete il comando e' di vanilla (`Commands.map.setKnownInSquares`
--- in ClientCommands), quindi non serve niente di nostro.
function C.reveal(player, x1, y1, x2, y2)
    pcall(function()
        WorldMapVisited.getInstance():setKnownInSquares(x1, y1, x2, y2)
    end)
    if isClient() and player then
        pcall(function()
            sendClientCommand(player, "map", "setKnownInSquares",
                { x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
        end)
    end
end

--- Porta i segni di questa mappa sulla mappa del mondo di chi legge.
---
--- UNIONE, MAI SOSTITUZIONE: quello che c'e' gia' non si tocca, e quello che
--- arriva si aggiunge se non c'e' gia' un segno uguale nello stesso posto. Una
--- mappa che si travasa due volte non raddoppia niente.
---
--- Torna quanti tratti e quanti simboli sono entrati davvero.
function C.transfer(item, player)
    if not (item and player) then return 0, 0 end
    local md = modDataOf(item)
    local d = md and md.NeatWriting
    if not d then return 0, 0 end

    -- La tabella del giocatore: nella modData da soli, in un file in rete
    -- (NW_PlayerStore, dove sta il perche').
    local mine = NW_PlayerStore.root(player, true)
    if not mine then return 0, 0 end
    mine.v = mine.v or NW_MapDoc.VERSION

    -- I tratti. Due tratti sono lo stesso se hanno gli stessi punti: la
    -- firma e' la stringa dei punti, che e' gia' come viaggiano in rete.
    local world = mine.worldInk
    if type(world) ~= "table" then world = {} mine.worldInk = world end
    -- LA FIRMA SI FA ALLA PRECISIONE CON CUI I PUNTI VIAGGIANO, non a quella con
    -- cui stanno in memoria.
    --
    -- `N.pack` formatta ogni coordinata con `%.2f`, quindi un tratto che ha
    -- fatto il giro del server torna arrotondato al centesimo mentre l'originale
    -- sulla mappa del mondo ha ancora la precisione piena. Confrontando i numeri
    -- come sono, le due stringhe non coincidono e lo stesso identico tratto
    -- sembra nuovo: si travasava una mappa e il suo tratto si aggiungeva a uno
    -- che c'era gia', sovrapposto e invisibile.
    --
    -- Arrotondando tutti e due si confronta quello che il tratto E' - un
    -- centesimo di quadrato e' un millesimo di pixel a qualunque zoom - invece
    -- di come e' scritto adesso.
    local function inkKey(pts)
        local parts = {}
        for i = 1, #pts do parts[i] = string.format("%.2f", pts[i]) end
        return table.concat(parts, ",")
    end

    local seen = {}
    for _, s in ipairs(world) do
        if type(s.p) == "table" then seen[inkKey(s.p)] = true end
    end
    local addedInk = 0
    -- Con il disegno a mano libera spento dalla partita (opzione sandbox) i
    -- tratti di una mappa trovata restano sul foglio: travasarli sarebbe
    -- disegnare sulla mappa del mondo per un'altra strada. I simboli passano.
    local inkIn = NW_Net.freehandAllowed() and d.ink or {}
    for _, s in ipairs(inkIn) do
        if type(s.p) == "table" then
            local key = inkKey(s.p)
            if not seen[key] then
                seen[key] = true
                world[#world + 1] = { w = s.w, c = s.c, p = s.p }
                addedInk = addedInk + 1
            end
        end
    end

    -- I simboli vanno nell'archivio di vanilla, non nel nostro: la mappa del
    -- mondo li tiene lei, e sono suoi. Si mettono alla prossima apertura, e
    -- intanto restano qui in attesa - la mappa del mondo potrebbe non essere
    -- nemmeno aperta nel momento in cui si legge il foglio.
    local pending = mine.pendingSym
    if type(pending) ~= "table" then pending = {} mine.pendingSym = pending end
    -- Anche qui unione e non accodamento. Premendo il tasto tre volte di fila -
    -- che e' la prima cosa che fa chiunque non veda succedere niente sullo
    -- schermo - la coda si riempiva di tre copie sovrapposte degli stessi
    -- simboli, e alla prossima apertura della mappa sarebbero state posate
    -- tutte e tre nello stesso punto.
    local seenSym = {}
    for _, e in ipairs(pending) do seenSym[symKey(e)] = true end
    local addedSym = 0
    for _, e in ipairs(d.sym or {}) do
        local key = symKey(e)
        if not seenSym[key] then
            seenSym[key] = true
            pending[#pending + 1] = e
            addedSym = addedSym + 1
        end
    end

    NW_PlayerStore.persist(player)

    -- E LA COPIA VIVA VA BUTTATA, o quello che abbiamo appena scritto muore.
    --
    -- NW_MapDoc tiene i tratti della mappa aperta in una lista in memoria,
    -- caricata una volta sola (`nwInkLoaded`), e al salvataggio successivo e'
    -- QUELLA a riscrivere la modData. Il travaso invece scrive dritto nella
    -- modData, alle spalle della lista: il primo `touch` della mappa del mondo
    -- la sovrascriveva e i tratti travasati sparivano senza un errore.
    --
    -- Da fuori si vedeva cosi': si travasava la stessa mappa due volte e il
    -- conto ripartiva da capo - "3 tratti" tutte e due le volte - perche' del
    -- primo travaso non era rimasto niente da riconoscere.
    --
    -- Si azzerano tutt'e due le cache, quella di NW_MapDoc e quella di NW_Ink,
    -- che si tengono per mano: la seconda conserva un riferimento alla lista
    -- della prima, e liberarne una sola lascerebbe l'altra a puntare la vecchia.
    local ui = ISWorldMap_instance
    if ui then
        ui.nwInkLoaded = false
        ui.nwInkList = nil
        ui.nwStrokes = nil
    end

    local x1, y1, x2, y2 = C.bounds(item)
    if x1 then C.reveal(player, x1, y1, x2, y2) end

    return addedInk, addedSym
end

--- I simboli in attesa, messi sulla mappa del mondo appena si apre.
---
--- Non si possono mettere quando arriva la mappa di carta: l'archivio dei
--- simboli e' quello della finestra della mappa del mondo, e quella finestra
--- puo' non esistere. Si mettono qui, una volta, e la lista si svuota.
function C.drainPending(mapUI, player)
    if not (mapUI and player) then return 0 end
    local mine = NW_PlayerStore.root(player, false)
    local pending = mine and mine.pendingSym
    if type(pending) ~= "table" or #pending == 0 then return 0 end

    local sapi
    pcall(function() sapi = mapUI.symbolsUI and mapUI.symbolsUI.symbolsAPI end)
    if not sapi then return 0 end

    local layer
    pcall(function() layer = sapi:getDefaultTextLayerID() end)

    -- Quello che c'e' gia' sulla mappa non si rimette. E' la stessa guardia di
    -- NW_MapDoc.restoreSymbols, e serve per lo stesso motivo: travasare due
    -- volte la stessa mappa, o travasarne due che si sovrappongono, non deve
    -- lasciare due simboli identici nello stesso quadrato.
    local present = {}
    pcall(function()
        for i = 1, sapi:getSymbolCount() do
            local s = sapi:getSymbolByIndex(i - 1)
            local e = {}
            e.x, e.y = s:getWorldX(), s:getWorldY()
            if s:isText() then
                e.t, e.id = "txt", textOf(s)
            else
                e.t, e.id = "tex", s:getSymbolID()
            end
            present[symKey(e)] = true
        end
    end)

    local waiting = #pending
    local put, already = 0, 0
    for _, e in ipairs(pending) do
        if present[symKey(e)] then
            -- Un `and false or pcall(...)` qui sarebbe stata una guardia che non
            -- guarda: `false or pcall(...)` valuta comunque il pcall, e il
            -- simbolo si sarebbe posato lo stesso.
            already = already + 1
        else
            local ok = pcall(function()
                local s
                if e.t == "txt" then
                    if layer then s = NW_MapDoc.addNote(sapi, e.id, layer, e.x, e.y) end
                else
                    s = sapi:addTexture(e.id, e.x, e.y)
                end
                if s then
                    s:setRGBA(e.r or 0, e.g or 0, e.b or 0, e.a or 1)
                    s:setAnchor(e.ax or 0.5, e.ay or 0.5)
                    if e.s then s:setScale(e.s) end
                    if e.rot then s:setRotation(e.rot) end
                    -- In rete un simbolo nuovo va annunciato, o lo vede solo chi
                    -- l'ha messo e sparisce alla prossima sincronizzazione.
                    if isClient() and sapi.sendModifySymbol then
                        sapi:sendModifySymbol(s)
                    end
                end
            end)
            if ok then
                present[symKey(e)] = true
                put = put + 1
            end
        end
    end

    mine.pendingSym = nil
    NW_PlayerStore.persist(player)
    -- L'ultimo passaggio del travaso, e finora era muto. Fra "i simboli non
    -- sono mai partiti", "sono partiti e non si sono posati" e "si sono posati
    -- e non si vedono" ci sono tre guasti diversi in tre posti diversi, e senza
    -- questa riga producono tutti e tre lo stesso schermo. Chi era gia' li' si
    -- conta a parte: e' l'unico modo di distinguere "non ho fatto niente
    -- perche' c'era gia' tutto" da "non ho fatto niente e non so perche'".
    if NW_NetClient and NW_NetClient.verbose then
        print("NW_Cartography: posati " .. put .. " simboli su " .. waiting
            .. " in attesa (" .. already .. " c'erano gia')")
    end
    return put
end

--- Vero se questo e' uno dei nostri oggetti mappa.
function C.isOurs(item)
    if not item then return false end
    local id
    pcall(function() id = item:getMapID() end)
    return id == C.ANNOTATED
end

return NW_Cartography
