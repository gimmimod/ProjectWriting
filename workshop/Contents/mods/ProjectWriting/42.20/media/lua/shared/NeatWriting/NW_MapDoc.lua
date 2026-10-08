--[[ ============================================================================
    NW_MapDoc - dove restano i tratti a mano libera disegnati su una mappa.

    DUE COSE, salvate per due ragioni diverse.

    I TRATTI A MANO LIBERA vanilla non li ha, quindi non ha nemmeno dove
    metterli: stavano su un campo dell'oggetto UI (`mapUI.nwStrokes`) e alla
    chiusura della mappa se ne andavano con lui. Si disegnava, si chiudeva, e
    non era mai successo niente.

    I SIMBOLI E I BIGLIETTI invece li tiene vanilla, nel suo archivio di
    annotazioni, che su una mappa di carta e' legato all'oggetto. In teoria
    basta; in pratica su una mappa annotata non bastava, e alla riapertura
    quello che si era aggiunto non c'era piu'. Se ne tiene percio' una copia
    nostra, che si rimette solo dove manca (M.captureSymbols / M.restoreSymbols,
    in fondo al file).

    DUE POSTI, perche' ci sono due mappe:

      * una mappa di carta e' un oggetto dell'inventario (`mapUI.mapObj`), e i
        suoi tratti stanno nella modData di quell'oggetto: la mappa passa di
        mano e il disegno ci va insieme;
      * la mappa del mondo non e' di nessuno ed e' di tutti - vanilla ci tiene
        le annotazioni per giocatore - quindi i tratti stanno nella modData del
        giocatore.

    LE COORDINATE SONO DEL MONDO, non dello schermo: sono le stesse che
    NW_Brush riceve da uiToWorldX/Y. Cosi' un tratto salvato torna dov'era
    qualunque sia lo zoom o la finestra alla riapertura.

    LA FORMA E' QUELLA DELLA PAGINA: `{ w = spessore, c = idInchiostro,
    p = { x1, y1, x2, y2, ... } }`, la stessa che NW_Doc scrive nelle pagine, e
    NW_Brush disegna l'una e l'altra con lo stesso codice.

    LO SPESSORE E' UN NUMERO DI PENNA, non una misura: quanti pixel diventi lo
    decide chi disegna, guardando l'ingrandimento del momento (NW_Brush).
============================================================================ ]]--

NW_MapDoc = NW_MapDoc or {}
local M = NW_MapDoc

M.VERSION = 1

--- Ogni quanto, al massimo, si scrive davvero. Disegnare produce un tratto per
--- gesto, non uno al frame, ma cancellare a trascinamento ne toglie tanti di
--- fila: senza freno si scriverebbe la modData a ogni pixel di movimento.
local SAVE_MS = 1000

-- ---------------------------------------------------------------------------
-- Quanto puo' pesare un disegno
-- ---------------------------------------------------------------------------
--
-- UN TETTO C'E' COMUNQUE, E NON E' NOSTRO. Un oggetto del giocatore salvato nel
-- database si ferma a 2 MB, e i tratti di una mappa di carta stanno nella
-- modData di quell'oggetto; la mappa del mondo sta invece nella modData del
-- GIOCATORE, che in rete viaggia INTERA a ogni spedizione. Senza un limite
-- nostro, il limite lo mette il motore - e lo mette rompendo qualcosa, non
-- dicendolo.
--
-- Quindi il tetto lo mettiamo prima noi, e ben sotto: quando il disegno ci
-- arriva vicino la penna si ferma e lo dice. Chi vuole continuare cancella
-- qualcosa, che e' l'unica decisione che spetta a lui e non a noi. La gomma
-- resta sempre disponibile: bloccare anche quella vorrebbe dire chiudere il
-- disegno in una stanza senza porta.
--
-- LA MISURA E' IN PUNTI, contati come li conta `peso-tratti.js`: sedici byte a
-- punto, cioe' otto per numero. E' una stima, e deve restare la stessa stima di
-- NW_Cartography (`chars = chars + #pts * 8`), o due parti della stessa mod
-- direbbero due pesi diversi dello stesso disegno.
local BYTE_PER_NUMERO = 8

--- Il tetto, in byte stimati, per le due superfici.
---
--- La mappa del mondo ha il tetto piu' basso e non perche' ci stia meno roba:
--- perche' quello che ci si disegna viaggia in rete addosso al giocatore, e un
--- pacchetto grosso su un server e' un guaio di tutti, non solo suo. 150 KB
--- sono circa trentacinque scarabocchi fitti o centocinquanta cerchi.
---
--- Una mappa di carta e' un oggetto che si porta in tasca: il muro del motore
--- e' a 2 MB e li' dentro ci stanno anche le pagine e il resto, quindi 700 KB
--- e' abbondante e resta lontano dal muro.
M.MAX_WORLD = 150000
M.MAX_ITEM  = 700000

--- Quanto pesa, adesso, il disegno di questa mappa.
function M.weight(mapUI)
    local list = mapUI and mapUI.nwInkList
    if not list then return 0 end
    local n = 0
    for _, s in ipairs(list) do
        local pts = s.pts or s.p
        if pts then n = n + #pts end
    end
    return n * BYTE_PER_NUMERO
end

--- Il tetto di QUESTA mappa.
function M.budget(mapUI)
    if mapUI and mapUI.mapObj then return M.MAX_ITEM end
    return M.MAX_WORLD
end

--- Non ci sta piu' niente: la penna si ferma.
function M.isFull(mapUI)
    if not (mapUI and mapUI.nwInkLoaded) then return false end
    return M.weight(mapUI) >= M.budget(mapUI)
end

--- La modData giusta per questa mappa, piu' la chiave dentro cui guardare.
---
--- Torna anche l'oggetto da sincronizzare, che non e' lo stesso nei due casi:
--- per una mappa di carta e' l'oggetto, per la mappa del mondo il giocatore.
--- La modData si chiede: `getModData` c'e' su un oggetto dell'inventario come
--- su un giocatore, e il pcall basta a coprire il caso in cui non ci sia niente
--- da chiedere.
local function where(mapUI, player)
    if not mapUI then return nil end
    local item = mapUI.mapObj
    if item then
        local md
        pcall(function() md = item:getModData() end)
        if md then return md, "ink", item, nil end
    end
    if player then
        -- In rete la tabella del giocatore sta in un file del client
        -- (NW_PlayerStore): la si presenta come se fosse la sua modData, cosi'
        -- il resto di questo file non deve sapere dove sta.
        local PS = rawget(_G, "NW_PlayerStore")
        if PS and PS.isFileBacked() then
            local root = PS.root(player, true)
            if root then return { NeatWriting = root }, "worldInk", nil, player end
            return nil
        end
        local md
        pcall(function() md = player:getModData() end)
        if md then return md, "worldInk", nil, player end
    end
    return nil
end

--- La nostra tabella dentro una modData, creata solo se serve davvero.
local function doc(md, create)
    if not md then return nil end
    local d = md.NeatWriting
    if not d then
        if not create then return nil end
        d = { v = M.VERSION }
        md.NeatWriting = d
    end
    -- Le versioni future si riconoscono da qui. Finche' ce n'e' una sola non
    -- c'e' niente da convertire, ma il numero c'e' gia' e va tenuto scritto.
    d.v = d.v or M.VERSION
    return d
end

--- I tratti di questa mappa, letti dalla memoria la prima volta e poi tenuti
--- sull'oggetto UI: si disegnano trenta volte al secondo, e rileggere la
--- modData a ogni frame sarebbe uno spreco per niente.
---
--- La lista che torna e' VIVA: aggiungere e togliere qui dentro e' come
--- disegnare e cancellare. Chi la tocca chiama poi M.touch.
function M.strokes(mapUI, player)
    if not mapUI then return {} end
    if mapUI.nwInkLoaded then return mapUI.nwInkList end

    local list = {}
    local md, key, item = where(mapUI, player)
    local d = md and doc(md, false)
    local saved = d and d[key]
    if type(saved) == "table" then
        for _, s in ipairs(saved) do
            if type(s) == "table" and type(s.p) == "table" and #s.p >= 4 then
                -- SI RILEGGE IN `pts`, che e' il nome con cui NW_Brush disegna.
                --
                -- In memoria un tratto sta in `p` (la forma compatta, la stessa
                -- delle pagine), ma NW_Brush.render legge `pts`: rimessi in
                -- lista con la chiave sbagliata, i tratti c'erano, erano salvati
                -- e non li disegnava nessuno. Da fuori era identico a non
                -- salvarli. Sulla pagina non si vedeva perche' li' a disegnare
                -- e' NW_Page:paintStroke, che accetta tutt'e due i nomi.
                list[#list + 1] = { w = s.w or 3.0, c = s.c or "black", pts = s.p }
            end
        end
    end

    mapUI.nwInkList = list
    mapUI.nwInkLoaded = true

    -- Quanti tratti sono usciti dalla memoria, e da quale delle due memorie.
    -- Serve per una domanda che il disegno da solo non sa rispondere: se una
    -- mappa si apre senza i tratti che dovrebbe avere, sono stati salvati male
    -- o riletti male? Qui si vede quanti ce n'erano scritti.
    if NW_NetClient and NW_NetClient.verbose and item then
        print("NW_MapDoc: " .. #list .. " tratti riletti dall'oggetto (ne erano scritti "
            .. tostring(type(saved) == "table" and #saved or 0) .. ")")
    end
    return list
end

--- Scrive i tratti nella memoria e, in rete, li spedisce.
---
--- `now` salta il freno: si usa alla chiusura della mappa, dove non c'e' un
--- dopo in cui recuperare.
function M.touch(mapUI, player, now)
    if not mapUI or not mapUI.nwInkLoaded then return end
    local t = getTimestampMs and getTimestampMs() or 0
    if not now and t - (mapUI.nwInkAt or 0) < SAVE_MS then
        mapUI.nwInkDirty = true
        return
    end
    mapUI.nwInkAt = t
    mapUI.nwInkDirty = false

    local md, key, item, ply = where(mapUI, player)
    if not md then return end
    local d = doc(md, true)

    -- Una lista vuota si toglie invece di restare a zero elementi: un oggetto
    -- su cui non si e' mai disegnato non deve portarsi dietro una tabella.
    local list = mapUI.nwInkList or {}
    if #list == 0 then
        d[key] = nil
    else
        -- Si scrive sempre in `p`: la lista viva mescola tratti appena chiusi
        -- (che arrivano da NW_Brush con `pts`) e tratti riletti dalla memoria.
        local out = {}
        for _, s in ipairs(list) do
            local pts = s.pts or s.p
            if pts and #pts >= 4 then out[#out + 1] = { w = s.w, c = s.c, p = pts } end
        end
        d[key] = out
    end

    -- In rete: l'oggetto porta la sua modData con syncItemModData, il giocatore
    -- con transmitModData. Si controlla che i nomi esistano invece di fidarsi
    -- del pcall - in Kahlua chiamare un nil e' un'eccezione Java e il pcall non
    -- la ferma (lezione 33).
    if item and ply == nil then
        if syncItemModData and player then
            pcall(function() syncItemModData(player, item) end)
        end
    elseif ply then
        -- IL GIOCATORE SI SPEDISCE ALLA CHIUSURA, NON OGNI SECONDO.
        --
        -- La modData di un giocatore viaggia INTERA a ogni transmitModData: non
        -- si spedisce il tratto nuovo, si spedisce tutto il disegno da capo. Un
        -- foglio di mappa lavorato bene sta in centinaia di chilobyte
        -- (`strumenti/controlli/peso-tratti.js`: fino a 8,7 KB per tratto), e
        -- rispedirlo una volta al secondo mentre la mano si muove e' il modo
        -- classico in cui una mod da disegno rende un server inservibile.
        --
        -- In casa non cambia niente: la memoria e' gia' scritta qui sopra, e
        -- una partita da soli non spedisce niente a nessuno. In rete si spedisce
        -- quando la mappa si chiude (`now`, cioe' M.flush), che e' l'unico
        -- momento in cui "fra un secondo" sarebbe troppo tardi.
        local PS = rawget(_G, "NW_PlayerStore")
        if PS and PS.isFileBacked() then
            -- In un file del client: si scrive li', e la rete non vede niente.
            PS.persist(ply)
        elseif now or not isClient() then
            pcall(function() ply:transmitModData() end)
        end
    end
end

--- Il debito lasciato dal freno, saldato quando il tempo e' passato.
--- Alla chiusura della mappa. Scrive SEMPRE, anche se il freno non aveva
--- niente in sospeso: in rete questa e' anche l'unica spedizione del disegno
--- (M.touch), e saltarla perche' "era gia' scritto in casa" vorrebbe dire
--- perderlo al primo rientro.
function M.flush(mapUI, player)
    if not (mapUI and mapUI.nwInkLoaded) then return end
    M.touch(mapUI, player, true)
end

-- ---------------------------------------------------------------------------
-- I simboli e i biglietti di una mappa di carta
-- ---------------------------------------------------------------------------
--
-- PERCHE' LI SALVIAMO NOI. Un simbolo posato sulla mappa passa dall'archivio di
-- vanilla (`symbolsAPI`), e su una mappa di carta quell'archivio e' legato
-- all'oggetto da `setMapItem`. In teoria basta. In pratica, su una mappa
-- annotata da un sopravvissuto, quello che si aggiunge alla riapertura non c'e'
-- piu': si scrive, si chiude, e la carta e' tornata com'era.
--
-- Invece di indovinare cosa faccia il motore, si tiene una copia nostra. E'
-- l'unico modo di poterlo garantire, ed e' lo stesso ragionamento dei tratti a
-- mano libera: quello che la mod si tiene da parte sta nella modData.
--
-- IL DOPPIONE NON SI FORMA, e questo e' il punto delicato. Alla riapertura si
-- rimette SOLO quello che non c'e' gia': si confronta per tipo, testo o
-- immagine, e posizione arrotondata all'unita' di mondo. Cosi' i due casi
-- possibili vanno bene tutti e due - se il motore li ha salvati per conto suo
-- non si tocca niente, se non li ha salvati tornano al loro posto - e i timbri
-- del sopravvissuto, che `doBuildingStash` riapplica a ogni apertura, si
-- riconoscono e si saltano.

local function symbolsAPI(mapUI)
    local sui = mapUI and mapUI.symbolsUI
    return sui and sui.symbolsAPI or nil
end

--- La chiave con cui due simboli sono "lo stesso".
local function symKey(e)
    return (e.t or "?") .. "|" .. tostring(e.id) .. "|"
        .. math.floor((e.x or 0) + 0.5) .. "|" .. math.floor((e.y or 0) + 0.5)
end


--- Il testo di un biglietto, comunque sia stato messo.
---
--- Due funzioni, due significati: `getTranslatedText` da' il testo vero, quello
--- scritto a mano; `getUntranslatedText` da' la CHIAVE di traduzione, e vale
--- solo per i biglietti che vanilla considera traduzioni. Un simbolo ha l'una o
--- l'altra, mai tutt'e due, e vanilla stessa distingue i due casi cosi':
---
---     local isTranslation = symbol:getUntranslatedText() ~= nil
---
--- Leggerne una sola voleva dire perdere meta' dei biglietti.
-- ---------------------------------------------------------------------------
-- I biglietti e il traduttore del gioco
-- ---------------------------------------------------------------------------
--
-- UN "%" IN UN BIGLIETTO ROMPEVA LA MAPPA. WorldMapTextSymbol ha due modi di
-- tenere un testo (letto nel bytecode):
--
--   setTranslatedText   translated = true    il testo si mostra com'e'
--   setUntranslatedText translated = false   il testo e' una CHIAVE: a ogni
--                                            misura e a ogni clic passa da
--                                            Translator.getText
--
-- Vanilla usa il secondo solo per le annotazioni con la spunta "e' una
-- traduzione" dell'editor delle mappe; un biglietto scritto a mano va col primo
-- (ISWorldMapSymbols, onNoteAdded). Noi li facevamo tutti col secondo. Per un
-- testo qualunque getText restituisce il testo stesso e non se ne accorgeva
-- nessuno; con un "%" dentro, la formattazione di Java alza un'eccezione -
-- anche dentro il log del gioco, che la riformatta - e hitTest, layout e il
-- nostro "chi l'ha scritto" cadevano a ogni clic (lezione 28, dal lato opposto).
--
-- E I DUE GETTER NON SONO SIMMETRICI: getTranslatedText su una chiave CHIAMA
-- getText, getUntranslatedText no (e su un testo normale torna nil).
--
-- PER UN ANALFABETA tutti e due tornano il testo con ogni carattere che non e'
-- uno spazio cambiato in "?": il testo vero non si puo' leggere, e quindi non si
-- riscrive mai niente mentre gioca lui.

--- Il testo che il biglietto MOSTRA, letto senza mai dare al traduttore un "%".
---
--- Il testo mostrato, non la chiave: e' quello che questo file ha sempre
--- salvato e confrontato (symKey), e cambiarlo farebbe sembrare nuove - e
--- riposare doppie - le note gia' salvate delle mappe dei nascondigli.
--- Una chiave vera non contiene "%", e il suo testo tradotto si chiede; una
--- "chiave" col "%" e' un biglietto scritto a mano salvato male, e il suo testo
--- e' lei stessa.
function M.noteText(s)
    local raw
    pcall(function() raw = s:getUntranslatedText() end)
    if raw ~= nil and raw:find("%", 1, true) then return raw end
    local t
    pcall(function() t = s:getTranslatedText() end)
    return t or raw
end

local textOf = M.noteText

--- Posa un biglietto come TESTO, com'e' quello di vanilla: si mostra com'e' e
--- non passa mai dal traduttore. Anche quando si rimette una nota letta da una
--- mappa dei nascondigli: quello salvato e' gia' il suo testo tradotto, e prima
--- lo si riposava come chiave solo per sentirselo restituire identico.
function M.addNote(sapi, text, layer, x, y)
    return sapi:addTranslatedText(tostring(text or ""), layer, x, y)
end

local function illiterate()
    local p = getPlayer and getPlayer()
    if not p then return false end
    local ok, res = pcall(function() return p:hasTrait(CharacterTrait.ILLITERATE) end)
    return ok and res == true
end

--- Rimette a posto i biglietti gia' salvati come chiave con un "%" dentro:
--- quelli scritti dalle versioni precedenti, e quelli che arrivano dalla rete da
--- chi non ha ancora aggiornato. Diventano testo, com'erano per chi li ha
--- scritti. Si rifa' quando cambia il numero di simboli, e comunque ogni pochi
--- secondi: un biglietto modificato dalla rete non cambia il conto.
---
--- VA CHIAMATA FUORI DAL DISEGNO DELLA MAPPA (NW_Map): e' proprio il disegno
--- che un biglietto rotto fa cadere.
---
--- Non si spedisce: ogni client ripara la propria copia, e il server non
--- disegna.
local RECHECK_MS = 3000

function M.repairNotes(holder, sapi)
    if not (holder and sapi) then return end
    local n
    pcall(function() n = sapi:getSymbolCount() end)
    if not n then return end
    local now = getTimestampMs and getTimestampMs() or 0
    if n == holder.nwNotesChecked and now - (holder.nwNotesAt or 0) < RECHECK_MS then return end
    if illiterate() then return end
    holder.nwNotesChecked = n
    holder.nwNotesAt = now
    for i = 0, n - 1 do
        -- Solo i biglietti: un simbolo-immagine questi metodi non li ha, e
        -- chiamare un metodo che non c'e' non lo ferma nessun pcall (lezione 33).
        local s
        pcall(function() s = sapi:getSymbolByIndex(i) end)
        local isText = false
        if s then pcall(function() isText = s:isText() == true end) end
        if isText then
            pcall(function()
                local key = s:getUntranslatedText()
                if key and key:find("%", 1, true) then s:setTranslatedText(key) end
            end)
        end
    end
end

--- Legge un simbolo dell'archivio di vanilla nella nostra forma.
local function readOne(s)
    local e = {}
    local ok = pcall(function()
        e.x, e.y = s:getWorldX(), s:getWorldY()
        e.r, e.g, e.b = s:getRed(), s:getGreen(), s:getBlue()
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
    if not ok or not e.t or e.id == nil then return nil end
    return e
end

--- Tutto quello che c'e' adesso sulla mappa, nella nostra forma.
local function readAll(mapUI)
    local sapi = symbolsAPI(mapUI)
    if not sapi then return nil end
    local out = {}
    local ok = pcall(function()
        for i = 1, sapi:getSymbolCount() do
            local e = readOne(sapi:getSymbolByIndex(i - 1))
            if e then out[#out + 1] = e end
        end
    end)
    if not ok then return nil end
    return out
end

--- Mette via i simboli di questa mappa. Solo per le mappe di carta: quella del
--- mondo ha il suo archivio, che vanilla salva per conto suo e che sarebbe
--- lungo migliaia di voci.
function M.captureSymbols(mapUI, player)
    if not mapUI or not mapUI.mapObj then return end
    local list = readAll(mapUI)
    if not list then return end

    local md
    pcall(function() md = mapUI.mapObj:getModData() end)
    local d = doc(md, true)
    if not d then return end
    d.sym = #list > 0 and list or nil

    if syncItemModData and player then
        pcall(function() syncItemModData(player, mapUI.mapObj) end)
    end
end

--- Rimette quello che manca. Da chiamare dopo che la mappa e' nata e dopo che
--- il deposito del sopravvissuto e' stato riapplicato: prima non si saprebbe
--- cosa c'e' gia'.
function M.restoreSymbols(mapUI)
    if not mapUI or not mapUI.mapObj then return end
    local md
    pcall(function() md = mapUI.mapObj:getModData() end)
    local d = doc(md, false)
    local saved = d and d.sym
    if type(saved) ~= "table" or #saved == 0 then return end

    local sapi = symbolsAPI(mapUI)
    if not sapi then return end

    local present = {}
    for _, e in ipairs(readAll(mapUI) or {}) do present[symKey(e)] = true end

    local layer
    pcall(function() layer = sapi:getDefaultTextLayerID() end)

    for _, e in ipairs(saved) do
        if type(e) == "table" and e.t and e.id ~= nil and not present[symKey(e)] then
            pcall(function()
                local s
                if e.t == "txt" then
                    if layer then s = M.addNote(sapi, e.id, layer, e.x, e.y) end
                else
                    s = sapi:addTexture(e.id, e.x, e.y)
                end
                if s then
                    s:setRGBA(e.r or 0, e.g or 0, e.b or 0, e.a or 1)
                    s:setAnchor(e.ax or 0.5, e.ay or 0.5)
                    if e.s then s:setScale(e.s) end
                    if e.rot then s:setRotation(e.rot) end
                end
            end)
            present[symKey(e)] = true
        end
    end
end
