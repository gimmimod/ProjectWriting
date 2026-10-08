--[[ ============================================================================
    NW_Doc - quello che c'e' scritto su un oggetto, e dove sta.

    Due depositi, e la divisione non e' arbitraria.

    IL TESTO STA DOVE LO METTE VANILLA. `item:addPage(n, testo)` e
    `item:seePage(n)` sono l'archivio del gioco, quello che il diario si porta
    dietro anche senza di noi: chi disinstalla la mod ritrova le sue pagine
    nella finestra di vanilla, e chi legge il diario di un altro giocatore le
    vede. Scriverle da un'altra parte sarebbe stato piu' comodo e sbagliato.

    Le pagine IN PIU' che offriamo - vanilla ne da' cinque a un blocco a spirale,
    e non esiste un modo di cambiarlo senza riscrivere i suoi script di oggetti,
    che vuol dire litigare con qualunque altra mod li tocchi - quelle stanno nel
    modData. Le prime restano di vanilla, le altre sono nostre, e chi chiede una
    pagina non deve sapere di chi e'.

    IL RESTO STA NEL MODDATA. Tratti a penna, simboli e biglietti non hanno un
    posto in vanilla, e vanno in `item:getModData().NeatWriting`. Le chiavi
    delle pagine sono stringhe: il modData attraversa un salvataggio e i numeri
    interi non sempre tornano interi.

    LE COORDINATE SONO QUELLE DELL'IMMAGINE, da 0,0 a width,height del supporto.
    Non pixel di schermo: cosi' quello che si scrive oggi su un monitor sta
    dov'era su un altro, e sopravvive anche a una texture rimpicciolita.

    SALVARE NON E' UN'AZIONE. Non c'e' un tasto: si scrive nell'oggetto mentre
    si disegna, perche' modData e pagine SONO l'oggetto. L'unica cosa che resta
    da fare e' avvisare il server in multigiocatore, ed e' quello che fa
    `touch()` - a intervalli, non a ogni tratto, altrimenti si spedirebbe la
    stessa pagina sessanta volte al secondo.
============================================================================ ]]--

NW_Doc = NW_Doc or {}
local D = NW_Doc

D.VERSION = 1

local SYNC_MS = 1500      -- ogni quanto, al massimo, si avvisa il server

-- ---------------------------------------------------------------------------
-- Il deposito
-- ---------------------------------------------------------------------------

--- Da una versione del deposito all'altra.
---
--- Oggi le versioni sono una sola e non c'e' niente da convertire, ma il posto
--- dove scriverlo esiste gia' e viene attraversato da ogni lettura: quando ce
--- ne sara' una seconda, la conversione andra' qui dentro e non sparsa nei
--- punti che leggono.
---
--- IL CASO CHE CAPITA DAVVERO NON E' IL PRIMO. Non e' un salvataggio vecchio
--- letto da una mod nuova - quello lo si prevede - ma il contrario: qualcuno
--- torna a una versione precedente della mod e si ritrova in mano una modData
--- scritta da una piu' recente. Li' l'unica cosa onesta e' non toccare niente e
--- non fingere di capirla: il testo delle pagine di vanilla resta leggibile
--- comunque, perche' quello non e' roba nostra.
function D.migrate(doc)
    if type(doc) ~= "table" then return doc end
    local v = tonumber(doc.v) or 0

    if v > D.VERSION then
        -- Piu' nuova di noi: si legge quello che si capisce e si lascia stare
        -- il resto. Riscrivere `v` la marchierebbe come nostra e la prossima
        -- versione la crederebbe gia' convertita.
        if type(doc.p) ~= "table" then doc.p = {} end
        return doc
    end

    -- Qui, un giorno: if v < 2 then ... doc.v = 2 end

    doc.v = D.VERSION
    return doc
end

--- Il nostro pezzo di modData. Si crea solo su richiesta: aprire un foglio per
--- guardarlo non deve lasciargli addosso una tabella vuota per sempre.
function D.get(item, create)
    if not item then return nil end
    local ok, md = pcall(function() return item:getModData() end)
    if not ok or not md then return nil end
    local doc = md.NeatWriting
    if type(doc) ~= "table" then
        if not create then return nil end
        doc = { v = D.VERSION, p = {} }
        md.NeatWriting = doc
    end
    if type(doc.p) ~= "table" then doc.p = {} end
    return D.migrate(doc)
end

--- La pagina `n`, creata se non c'e'. `n` e' la pagina di vanilla, da 1.
function D.page(item, n, create)
    local doc = D.get(item, create)
    if not doc then return nil end
    local key = tostring(n)
    local page = doc.p[key]
    if type(page) ~= "table" then
        if not create then return nil end
        page = {}
        doc.p[key] = page
    end
    return page
end

--- Una lista dentro una pagina: "ink", "sym", "note".
function D.list(item, n, which, create)
    local page = D.page(item, n, create)
    if not page then return nil end
    local l = page[which]
    if type(l) ~= "table" then
        if not create then return nil end
        l = {}
        page[which] = l
    end
    return l
end

-- ---------------------------------------------------------------------------
-- Il testo, che sta in vanilla
-- ---------------------------------------------------------------------------

--- Quante pagine dichiara vanilla. Sono quelle che si leggono anche senza di
--- noi, ed e' il motivo per cui restano le prime.
function D.vanillaPages(item)
    local ok, n = pcall(function() return item:getPageToWrite() end)
    if ok and n and n > 0 then return n end
    return 1
end

--- Il testo di una pagina.
---
--- Le prime stanno nell'archivio del gioco; quelle in piu' che offriamo noi -
--- vanilla ne dichiara cinque su un blocco a spirale, e non c'e' un modo di
--- cambiarlo senza riscrivere i suoi script - stanno nel modData. La divisione
--- si vede solo qui dentro: chi chiede la pagina 12 non deve sapere di chi e'.
function D.text(item, n)
    if n <= D.vanillaPages(item) then
        local ok, s = pcall(function() return item:seePage(n) end)
        if ok and type(s) == "string" then return s end
        return ""
    end
    local doc = D.get(item, false)
    local extra = doc and doc.t
    return (type(extra) == "table" and extra[tostring(n)]) or ""
end

function D.setText(item, n, s)
    if n <= D.vanillaPages(item) then
        pcall(function() item:addPage(n, s or "") end)
        return
    end
    local doc = D.get(item, true)
    if not doc then return end
    if type(doc.t) ~= "table" then doc.t = {} end
    doc.t[tostring(n)] = s or ""
end

--- C'e' qualcosa su questa pagina: testo, inchiostro, simboli o biglietti.
function D.pageHasContent(item, n)
    if D.text(item, n) ~= "" then return true end
    for _, which in ipairs({ "ink", "sym", "note" }) do
        local l = D.list(item, n, which, false)
        if l and #l > 0 then return true end
    end
    return false
end

--- L'ultima pagina con qualcosa sopra, o nil se l'oggetto e' vuoto. `pages` e'
--- quante pagine ha l'oggetto: si guarda dall'ultima all'indietro, perche' e'
--- la risposta che serve e un diario si riempie dall'inizio.
function D.lastWrittenPage(item, pages)
    for n = math.max(1, pages or 1), 1, -1 do
        if D.pageHasContent(item, n) then return n end
    end
    return nil
end

--- L'oggetto ha qualcosa scritto sopra, ovunque.
---
--- VANILLA LO CHIEDE A MODO SUO, E SBAGLIA SUI NOSTRI. `item:isEmptyPages()`
--- guarda solo le sue pagine di testo, e un diario scritto a penna o pieno di
--- simboli per lei e' vuoto: il menu diceva "Non contiene niente di
--- interessante" e spegneva la voce (NW_Context).
function D.hasContent(item)
    if not item then return false end
    local doc = D.get(item, false)
    if doc then
        for _, page in pairs(doc.p or {}) do
            if type(page) == "table" then
                for _, which in ipairs({ "ink", "sym", "note" }) do
                    if type(page[which]) == "table" and #page[which] > 0 then return true end
                end
            end
        end
        for _, s in pairs(type(doc.t) == "table" and doc.t or {}) do
            if type(s) == "string" and s ~= "" then return true end
        end
    end
    local ok, empty = pcall(function() return item:isEmptyPages() end)
    return ok and empty == false
end

--- Con che inchiostro e' scritto il testo di una pagina. Vanilla le pagine le
--- tiene, ma di colori non sa niente: quello e' nostro e sta nel modData.
function D.textInk(item, n)
    local page = D.page(item, n, false)
    return page and page.tc or nil
end

function D.setTextInk(item, n, id)
    if not id then return end
    local page = D.page(item, n, true)
    if page then page.tc = id end
end

-- ---------------------------------------------------------------------------
-- Il nome
-- ---------------------------------------------------------------------------

--- Rinomina l'oggetto come fa vanilla alla chiusura del diario: il nome e'
--- dell'oggetto, non di una nostra tabella, cosi' si legge anche nell'inventario.
function D.rename(item, name, player)
    if not item or not name or name == "" then return false end
    pcall(function()
        item:setName(name)
        item:setCustomName(true)
    end)
    D.touch(item, player, true)
    return true
end

function D.name(item)
    local ok, s = pcall(function() return item:getName() end)
    return ok and s or ""
end

-- ---------------------------------------------------------------------------
-- Multigiocatore
-- ---------------------------------------------------------------------------

--- Avvisa il server che l'oggetto e' cambiato. In singolo non fa niente di
--- visibile e non costa niente; in rete e' quello che fa arrivare la pagina
--- agli altri. `now` salta l'attesa, per le cose che non si ripetono - un nome,
--- la chiusura della finestra.
function D.touch(item, player, now)
    if not item then return end
    local t = getTimestampMs and getTimestampMs() or 0
    if not now then
        -- Un oggetto solo per volta: si scrive su un foglio alla volta, e tenere
        -- una tabella di tempi per oggetti che non si toccano piu' sarebbe una
        -- perdita che non finisce mai.
        if D.lastItem == item and t - (D.lastAt or 0) < SYNC_MS then return end
        D.lastItem, D.lastAt = item, t
    else
        D.lastItem, D.lastAt = item, t
    end
    -- DUE CHIAMATE, non una. syncItemFields spedisce i campi dell'oggetto, e
    -- fra quelli ci sono le pagine di vanilla: e' quello che usa il diario del
    -- gioco dopo addPage. La modData non ci viaggia dentro - per quella c'e'
    -- syncItemModData, che vanilla chiama accanto all'altra nella stessa riga
    -- di codice (ISChangeFishingRodEquip). Tutto quello che non sta nelle
    -- pagine di vanilla - inchiostro, simboli, biglietti e le pagine in piu' -
    -- sta nella modData, quindi senza la seconda in partita in rete l'altro non
    -- vede niente di nostro.
    --
    -- Si controlla che i nomi esistano invece di affidarsi al pcall: in Kahlua
    -- chiamare un nil non e' un errore Lua ma un'eccezione Java, e il pcall non
    -- la ferma (lezione 33).
    if player then
        if syncItemFields then pcall(function() syncItemFields(player, item) end) end
        if syncItemModData then pcall(function() syncItemModData(player, item) end) end
    else
        pcall(function() item:syncItemFields() end)
    end
end

return NW_Doc
