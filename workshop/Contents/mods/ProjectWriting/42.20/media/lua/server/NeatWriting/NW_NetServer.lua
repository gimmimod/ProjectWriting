--[[ ============================================================================
    NW_NetServer - il deposito dei tratti spartiti, e chi puo' vederli.

    Riceve dai client, controlla, conserva e ridistribuisce. Vale SOLO per i
    tratti a mano libera sulla mappa del mondo: i simboli e i biglietti di testo
    li spartisce vanilla per conto suo (`symbol:setSharing`), e una mappa di
    carta viaggia intera con l'oggetto.

    QUI E' L'UNICO POSTO DELLA MOD DOVE UN PERMESSO DECIDE QUALCOSA, e percio'
    non ci si fida mai del client: chi puo' vedere un tratto e chi puo'
    cancellarlo lo dice questo file, guardando fazione, rifugio e livello
    d'accesso. Un client puo' chiedere; rispondere tocca a qui.

    IL DEPOSITO sta nella modData del tempo di gioco - `getGameTime():getModData()` -
    che e' la memoria del mondo, quella che si salva col mondo. I punti dentro
    ci vanno **in stringa** (NW_Net.pack): una tabella dentro una tabella dentro
    la modData e' il tipo di annidamento che il serializzatore lascia per strada
    senza dirlo.

    DA SOLI FUNZIONA LO STESSO, ed e' voluto: il collaudo si fa su un server
    personale, giocando da soli, e li' la meta' server e questa meta' vivono
    nella stessa macchina virtuale. L'unica differenza e' come si consegna la
    risposta (NW_Net.deliver invece di sendServerCommand), perche' in
    singleplayer sendServerCommand non arriva a nessuno.
============================================================================ ]]--

--- SU UN CLIENT QUESTO FILE NON DEVE FARE NIENTE, e la guardia serve davvero:
--- il gioco carica `media/lua/server/` di una mod ANCHE nel processo del
--- client. Lo si e' visto perche' la riga di avvio qui sotto e' comparsa nei
--- due log insieme, quello del server coop e quello del client.
---
--- Senza questa riga il modulo esisteva in tutt'e due le macchine virtuali: una
--- riceveva i comandi e teneva il deposito vero, l'altra restava li' con un
--- deposito vuoto che non si sarebbe riempito mai. Ed e' esattamente quello che
--- il banco di prova leggeva quando diceva "server holds: 0" - non la tabella
--- sbagliata per modo di dire, proprio l'altra copia.
---
--- In singleplayer `isClient()` e' falso e il modulo lavora, che e' giusto: li'
--- le due meta' sono la stessa macchina virtuale.
if isClient() then return end

require "NeatWriting/NW_Net"

NW_NetServer = NW_NetServer or {}
local V = NW_NetServer
local N = NW_Net

--- Quanto parla, mentre si collauda.
---
--- IL SILENZIO NON E' UNA BUONA NOTIZIA, ed e' costato un giro di prove: dopo
--- il primo collaudo il log non aveva un solo errore nostro - e nemmeno una
--- riga che dicesse che questa meta' era viva. Un modulo che parla solo quando
--- va male e' indistinguibile da un modulo che non e' stato caricato affatto,
--- e su un server coop il processo e' un altro, con un log tutto suo.
---
--- Percio' quando e' accesa dice tre cose: che c'e', che ha accettato un
--- tratto, e che ha risposto a una sincronizzazione. Una riga per gesto, non
--- una al fotogramma.
---
--- VA SPENTA PRIMA DI PUBBLICARE. Un server vero ha decine di giocatori che
--- disegnano, e tre righe per gesto moltiplicate per loro sono un log che
--- nessuno legge piu' - il modo migliore per nascondere l'unica riga che
--- contava.
---
--- Spenta: la 1.2.1 si pubblica. Un giro di prove muto costa piu' di quanto
--- costi il rumore, quindi per collaudare si rimette true - qui e nel client.
V.verbose = false

local function say(text)
    if V.verbose then print("NW_NetServer: " .. text) end
end

--- Tutti i tratti che il mondo conosce, per id. In memoria mentre si gioca,
--- nella modData del tempo di gioco quando si salva.
local strokes = nil

-- ---------------------------------------------------------------------------
-- Il deposito
-- ---------------------------------------------------------------------------

local function store()
    local md
    pcall(function() md = getGameTime():getModData() end)
    return md
end

local function load()
    if strokes then return strokes end
    strokes = {}
    local md = store()
    local saved = md and md.NW_WorldInk
    if type(saved) == "table" then
        for id, s in pairs(saved) do
            if type(s) == "table" and type(s.p) == "string" then
                strokes[id] = {
                    id = id,
                    author = s.author or "?",
                    w = tonumber(s.w) or 3.0,
                    c = s.c or "black",
                    p = s.p,
                    share = type(s.share) == "table" and s.share or { mode = "all" },
                }
            end
        end
    end
    return strokes
end

local function save()
    local md = store()
    if not md then return end
    local out = {}
    for id, s in pairs(strokes or {}) do
        out[id] = { author = s.author, w = s.w, c = s.c, p = s.p, share = s.share }
    end
    md.NW_WorldInk = out
end

local function countOf(author)
    local n = 0
    for _, s in pairs(load()) do
        if s.author == author then n = n + 1 end
    end
    return n
end

local function total()
    local n = 0
    for _ in pairs(load()) do n = n + 1 end
    return n
end

-- ---------------------------------------------------------------------------
-- Chi e' chi
-- ---------------------------------------------------------------------------

--- Amministratore o moderatore, e nient'altro.
---
--- DA UNA PARTITA COOP OSPITATA DA STEAM NON SI E' AMMINISTRATORI, e vale la
--- pena saperlo prima di passarci un pomeriggio: la schermata del server ha un
--- campo "nome account" che vale `admin`, ma `CoopOptionsScreen` lo nasconde in
--- modalita' Steam, dove il nome utente e' quello dell'account. Chi ospita
--- quindi non ha il ruolo, e il server gli rispondera' di no come a chiunque
--- altro. Non e' un difetto di questo file. (lezione 54)
---
--- IL RUOLO SI GUARDA PER QUELLO CHE PUO' FARE, NON PER COME SI CHIAMA. Dalla
--- 42.13 i livelli d'accesso sono ruoli (Roles), e un server ne crea di suoi
--- con nomi suoi: `getAccessLevel()` restituisce solo il nome del ruolo. Prima
--- valevano soltanto "admin" e "moderator" scritti cosi', e un admin con un
--- ruolo chiamato in un altro modo non cancellava i tratti degli altri
--- (segnalazione 1.0.0, partita ospitata). Vale la capacita' che il gioco
--- stesso usa per le annotazioni altrui, EditMapSymbols (quella del comando
--- /removemapsymbols), oppure i poteri da amministratore; il nome resta come
--- ultima prova. I metodi si guardano prima di chiamarli: in Kahlua chiamare
--- un nil e' un'eccezione che il pcall non ferma (lezione 33).
local function isAdmin(player)
    if not player then return false end
    local yes = false
    pcall(function()
        local role = player.getRole and player:getRole() or nil
        if not role then return end
        local cap = Capability and Capability.EditMapSymbols
        if cap and role.hasCapability and role:hasCapability(cap) then yes = true end
        if not yes and role.hasAdminPower and role:hasAdminPower() then yes = true end
    end)
    if yes then return true end
    local level
    pcall(function() level = string.lower(tostring(player:getAccessLevel())) end)
    return level == "admin" or level == "moderator"
end

--- La fazione di questo nome, o nil.
---
--- `Faction.getFactions()` e' l'elenco intero: non c'e' un "dammi la fazione di
--- Tizio", quindi si guarda dentro una per una.
local function factionOf(username)
    if not (Faction and username) then return nil end
    local list
    pcall(function() list = Faction.getFactions() end)
    if not list then return nil end
    for i = 0, list:size() - 1 do
        local f = list:get(i)
        local yes = false
        pcall(function() yes = f:isOwner(username) or f:isMember(username) end)
        if yes then return f end
    end
    return nil
end

--- Il rifugio di questo nome, o nil.
---
--- Si chiede a `SafeHouse.getSafehouseList()`. NON esiste
--- `SafeHouse.getSafehouses()` in B42: chiamarla e' "Object tried to call nil",
--- ed e' l'errore che aveva rotto la condivisione per rifugio in
--- PZShareMapNotes prima che la correggessero.
local function safehouseOf(username)
    if not (SafeHouse and username) then return nil end
    local list
    pcall(function() list = SafeHouse.getSafehouseList() end)
    if not list then return nil end
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        local yes = false
        pcall(function()
            yes = tostring(sh:getOwner()) == username or sh:getPlayers():contains(username)
        end)
        if yes then return sh end
    end
    return nil
end

local function sameFaction(a, b)
    if a == b then return true end
    local f = factionOf(a)
    if not f then return false end
    local yes = false
    pcall(function() yes = f:isOwner(b) or f:isMember(b) end)
    return yes
end

local function sameSafehouse(a, b)
    if a == b then return true end
    local sh = safehouseOf(a)
    if not sh then return false end
    local yes = false
    pcall(function()
        yes = tostring(sh:getOwner()) == b or sh:getPlayers():contains(b)
    end)
    return yes
end

--- Questo tratto, questo spettatore: lo vede?
---
--- L'autore vede sempre il suo, e un amministratore vede tutto - senza quello
--- non potrebbe fare il suo mestiere, che e' anche cancellare quello che non
--- doveva esserci.
local function visibleTo(stroke, viewer, viewerIsAdmin)
    if not stroke then return false end
    if stroke.author == viewer then return true end
    if viewerIsAdmin then return true end
    local share = stroke.share or {}
    local mode = share.mode
    if mode == "all" then return true end
    if mode == "faction" then return sameFaction(stroke.author, viewer) end
    if mode == "safehouse" then return sameSafehouse(stroke.author, viewer) end
    if mode == "players" then
        for _, name in ipairs(share.players or {}) do
            if name == viewer then return true end
        end
        return false
    end
    return false   -- "private", e qualunque cosa non riconosciuta
end

--- Chi puo' cancellare questo tratto: chi l'ha fatto, un amministratore, e il
--- capo della fazione dell'autore.
---
--- E' il punto A4 delle note: "se hai il ruolo usi la gomma e cancelli
--- qualsiasi cosa". Il ruolo si guarda qui, non dove si preme il tasto.
local function mayRemove(stroke, username, player)
    if not stroke then return false end
    if stroke.author == username then return true end
    if isAdmin(player) then return true end
    local f = factionOf(stroke.author)
    if f then
        local owner = false
        pcall(function() owner = f:isOwner(username) end)
        if owner then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Parlare ai client
-- ---------------------------------------------------------------------------

--- Consegna al client di casa, in singleplayer.
---
--- Il pcall non e' cautela di troppo: in rete un errore del client non puo'
--- toccare i conti del server, e da soli deve restare cosi', o un'eccezione
--- nella meta' client tornerebbe indietro fin qui e lascerebbe il deposito a
--- meta'.
local function toSelf(command, args)
    if not N.deliver then
        print("NW_NetServer: da soli, ma la meta' client non c'e': perso " .. tostring(command))
        return
    end
    local ok, err = pcall(N.deliver, command, N.copy(args))
    if not ok then print("NW_NetServer: consegna locale fallita: " .. tostring(err)) end
end

local function toPlayer(player, command, args)
    if N.isSolo() then toSelf(command, args) return end
    sendServerCommand(player, N.MODULE, command, args)
end

--- A tutti quelli che possono vedere questo tratto, tranne l'autore: lui ce
--- l'ha gia' sotto gli occhi, glielo ha disegnato la sua stessa mano.
local function toEveryoneWhoMaySee(stroke, command, args)
    if N.isSolo() then return end
    local players = getOnlinePlayers()
    if not players then return end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local name = N.nameOf(p)
        if name ~= stroke.author and visibleTo(stroke, name, isAdmin(p)) then
            sendServerCommand(p, N.MODULE, command, args)
        end
    end
end

--- Un tratto come va spedito: cinque campi piatti e basta.
---
--- La condivisione NON parte: al client non serve - lui disegna e basta - e
--- `share` porterebbe una tabella dentro una tabella dentro il comando, che e'
--- il tipo di annidamento su cui il serializzatore del gioco lascia le cose
--- per strada senza dire niente. Meno livelli viaggiano, meno cose possono
--- arrivare a meta'.
local function netForm(s)
    return { id = s.id, author = s.author, w = s.w, c = s.c, p = s.p }
end

-- ---------------------------------------------------------------------------
-- I comandi che arrivano
-- ---------------------------------------------------------------------------

--- Un tratto e' accettabile?
---
--- Si guarda la stringa PRIMA di aprirla: un messaggio lungo un megabyte non
--- deve farci costruire la tabella e poi scartarla.
local function accept(args, username)
    if type(args) ~= "table" then return nil, "niente" end
    if type(args.p) ~= "string" then return nil, "senza punti" end
    if #args.p > N.MAX_POINT_CHARS then return nil, "troppo lungo" end
    local pts = N.unpack(args.p)
    if not pts then return nil, "punti illeggibili" end
    if #pts / 2 > N.MAX_POINTS_PER_STROKE then return nil, "troppi punti" end
    if countOf(username) >= N.MAX_STROKES_PER_AUTHOR then return nil, "tetto per autore" end
    if total() >= N.MAX_STROKES_TOTAL then return nil, "tetto del mondo" end

    -- La condivisione arriva PIATTA: `mode` e `players` come stringa di nomi
    -- separati da virgole. Nel comando non viaggia nessuna tabella dentro una
    -- tabella, che e' l'annidamento su cui il serializzatore del gioco lascia
    -- le cose per strada in silenzio. Qui dentro invece la si rimette in forma:
    -- il deposito e' roba nostra e puo' essere fatto come ci pare.
    local players = {}
    if type(args.players) == "string" and args.players ~= "" then
        for name in string.gmatch(args.players, "[^,]+") do
            players[#players + 1] = name
        end
    end
    local mode = tostring(args.mode or "all")

    return {
        id = tostring(args.id or N.strokeId(username)),
        author = username,          -- MAI quello che dice il client
        w = tonumber(args.w) or 3.0,
        c = tostring(args.c or "black"),
        p = N.pack(pts),            -- ripulita: si conserva quello che si e' letto
        share = { mode = mode, players = players },
    }
end

local function onStroke(player, args)
    local username = N.nameOf(player)
    -- L'opzione sandbox vale anche per chi non la rispetta: un client vecchio,
    -- o modificato, che spedisce lo stesso. Il tratto non entra nel deposito.
    if not N.freehandAllowed() then
        print("NW_NetServer: tratto rifiutato (disegno a mano libera spento) da " .. tostring(username))
        return
    end
    -- Con la mappa lasciata al gioco per tutti non c'e' un nostro disegno sulla
    -- mappa del mondo da spartire.
    if N.vanillaMapForced() then
        print("NW_NetServer: tratto rifiutato (mappa lasciata al gioco) da " .. tostring(username))
        return
    end
    local stroke, why = accept(args, username)
    if not stroke then
        print("NW_NetServer: tratto rifiutato (" .. tostring(why) .. ") da " .. tostring(username))
        return
    end
    load()[stroke.id] = stroke
    save()
    say("tratto di " .. username .. " accettato ["
        .. tostring(stroke.share and stroke.share.mode) .. "], " .. total() .. " in tutto")
    toEveryoneWhoMaySee(stroke, N.S_ADD, netForm(stroke))
end

local function onRemove(player, args)
    local username = N.nameOf(player)
    local id = args and tostring(args.id or "")
    local stroke = load()[id]
    -- Un tratto che il deposito non conosce: si risponde lo stesso, dicendo
    -- che non c'e'. Chi lo aveva sullo schermo se lo toglie e i due tornano a
    -- raccontare la stessa storia. Tacere lo lascerebbe li' per sempre, che e'
    -- il caso in cui un client ha qualcosa che il server ha gia' dimenticato.
    if not stroke then
        toPlayer(player, N.S_GONE, { id = id })
        return
    end
    if not mayRemove(stroke, username, player) then
        -- Si risponde di no, invece di tacere. Chi ha chiesto se lo segna e non
        -- richiede piu': senza risposta continuerebbe a chiedere finche' tiene
        -- la gomma premuta, che sono decine di pacchetti al secondo per un
        -- gesto solo. E' successo, e si leggeva nel log come una colonna di
        -- righe identiche.
        say(tostring(username) .. " non puo' cancellare " .. id)
        toPlayer(player, N.S_DENY, { id = id })
        return
    end
    load()[id] = nil
    save()
    say("tratto " .. id .. " tolto da " .. tostring(username) .. ", " .. total() .. " restano")
    -- La sparizione la devono sapere tutti quelli che lo vedevano, l'autore
    -- compreso: se a cancellarlo e' stato un amministratore, l'autore ce l'ha
    -- ancora sullo schermo.
    if N.isSolo() then
        toSelf(N.S_GONE, { id = id })
    else
        local players = getOnlinePlayers()
        for i = 0, (players and players:size() or 0) - 1 do
            local p = players:get(i)
            local name = N.nameOf(p)
            if visibleTo(stroke, name, isAdmin(p)) then
                sendServerCommand(p, N.MODULE, N.S_GONE, { id = id })
            end
        end
    end
end

--- "Ho aperto la mappa": si manda quello che questo giocatore puo' vedere, a
--- blocchi, perche' un comando solo con quattrocento tratti dentro e' un
--- pacchetto che nessuno vuole.
--- `args.mine` chiede di rimandare anche quelli di chi domanda.
---
--- Normalmente si saltano: chi ha disegnato ce l'ha gia' sotto gli occhi, e
--- rimandarglieli vorrebbe dire disegnarli due volte. Serve al banco di prova,
--- dove si gioca da soli e senza questo il giro non si vedrebbe mai chiudersi:
--- i propri tratti tornano indietro dal deposito, ed e' la prova che ci sono
--- arrivati davvero, con i punti giusti. Non e' un buco: sono i suoi.
local function onSync(player, args)
    local username = N.nameOf(player)
    local admin = isAdmin(player)
    local echo = type(args) == "table" and args.mine == true
    local batch, sent = {}, 0
    for _, s in pairs(load()) do
        if (echo or s.author ~= username) and visibleTo(s, username, admin) then
            batch[#batch + 1] = netForm(s)
            if #batch >= N.SYNC_BATCH then
                toPlayer(player, N.S_ALL, { strokes = batch })
                sent = sent + #batch
                batch = {}
            end
        end
    end
    if #batch > 0 then
        toPlayer(player, N.S_ALL, { strokes = batch })
        sent = sent + #batch
    end
    toPlayer(player, N.S_DONE, { count = sent, held = total() })
    say("sincronizzazione per " .. username .. ": " .. sent .. " spediti su "
        .. total() .. " nel deposito" .. (echo and " (echo)" or ""))
end


-- ---------------------------------------------------------------------------
-- Fabbricare una mappa
-- ---------------------------------------------------------------------------

--- Il client chiede, il server fabbrica e consegna.
---
--- PERCHE' NON LO FA IL CLIENT, che sarebbe piu' corto. Un oggetto nato con
--- `instanceItem` sul client il server non l'ha mai visto: quell'id per lui non
--- esiste. Il primo tentativo lo creava di la' e poi chiedeva di
--- sincronizzarne la modData, e il server rispondeva a ogni pressione
---
---     Error with packet of type: SyncItemFields
---     NullPointerException: ... because "item" is null
---
--- e l'oggetto spariva al primo riallineamento dell'inventario - il foglio di
--- carta invece restava, perche' anche quello lo aveva tolto solo il client.
--- Chi ha guardato dentro il proprio cadavere ha trovato esattamente questo:
--- niente mappa, e la carta ancora li'.
---
--- In vanilla un oggetto regalato a un giocatore lo crea SEMPRE il server:
--- `sendAddItemToContainer` sta in ClientCommands e nel campeggio, cioe' di
--- qua, mai di la'.
---
--- IL CARICO ARRIVA PIATTO. I punti dei tratti viaggiano gia' in stringa
--- (N.pack), e qui la lista intera diventa una stringa sola separata da `;`,
--- perche' una tabella dentro una tabella dentro un comando e' il livello che
--- il serializzatore lascia per strada senza dirlo. I simboli viaggiano allo
--- stesso modo, un campo per riga.
local function onMakeMap(player, args)
    if type(args) ~= "table" or not player then return end
    -- Il ritaglio e' una funzione della nostra mappa: con la mappa lasciata al
    -- gioco dalla sandbox il tasto non c'e', e un client che la chiede lo stesso
    -- non ottiene niente.
    if N.vanillaMapForced() then
        say("mappa rifiutata: mappa lasciata al gioco dalla sandbox")
        return
    end

    local x1, y1 = tonumber(args.x1), tonumber(args.y1)
    local x2, y2 = tonumber(args.x2), tonumber(args.y2)
    if not (x1 and y1 and x2 and y2) or x2 <= x1 or y2 <= y1 then
        say("mappa rifiutata: confini illeggibili")
        return
    end

    -- UN TIPO SOLO, e si controlla lo stesso. Il nome dell'oggetto da fabbricare
    -- arriva dal client, ed e' l'unico campo di questo comando che finisce in
    -- `instanceItem`: senza questa riga un client modificato potrebbe farsi
    -- consegnare qualunque cosa esista negli script del gioco.
    local kind = tostring(args.kind or "")
    if kind ~= "NW_AnnotatedMap" then
        say("mappa rifiutata: tipo sconosciuto " .. kind)
        return
    end

    local item
    pcall(function() item = instanceItem("Base." .. kind) end)
    if not item then
        say("mappa rifiutata: instanceItem non ha risposto")
        return
    end

    local md
    pcall(function() md = item:getModData() end)
    if not md then return end
    local d = { v = 1, mapAuthor = N.nameOf(player) }
    d.crop = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
    d.ink = N.unpackStrokes(args.ink)
    d.sym = N.unpackSymbols(args.sym)
    if type(args.seen) == "string" and args.seen ~= "" then
        d.seen = {}
        for k in string.gmatch(args.seen, "[^;]+") do d.seen[#d.seen + 1] = k end
    end
    md.NeatWriting = d

    local name = tostring(args.name or "")
    if name ~= "" then pcall(function() item:setName(name) end) end

    local inv
    pcall(function() inv = player:getInventory() end)
    if not inv then return end
    -- DUE COSE, NON UNA: prima si mette l'oggetto nel contenitore, poi lo si
    -- annuncia. E' la sequenza di vanilla (ClientCommands), e la prima volta ne
    -- avevo scritta solo la seconda meta':
    --
    --     player:getInventory():AddItem(...)          <- il server lo mette
    --     sendAddItemToContainer(inventario, oggetto) <- i client lo sanno
    --
    -- Annunciando e basta, il client vedeva la mappa comparire e il server non
    -- l'aveva mai avuta: al primo riallineamento dell'inventario spariva. Nel
    -- log si leggeva "mappa fabbricata" e nel cadavere non c'era niente, che e'
    -- il modo peggiore di sbagliare - il registro diceva di si'.
    pcall(function() inv:AddItem(item) end)
    pcall(function() sendAddItemToContainer(inv, item) end)
    -- La modData la porta questa, non l'annuncio: `syncItemFields` manda i campi
    -- dell'oggetto e non quello che ci abbiamo messo dentro noi, che qui e'
    -- tutta la mappa (lezione 35). Adesso la chiamata e' legittima, perche'
    -- l'oggetto esiste davvero da questa parte.
    if syncItemModData then
        pcall(function() syncItemModData(player, item) end)
    end

    -- E adesso, e solo adesso, si consuma il foglio: se qualcosa fosse andato
    -- storto qui sopra si sarebbe persa la carta senza avere la mappa. Anche
    -- qui due cose - togliere e annunciare - perche' annunciando soltanto il
    -- foglio restava nell'inventario del server e tornava indietro da solo.
    local paperId = tonumber(args.paper)
    if paperId then
        pcall(function()
            local paper = inv:getItemWithID(paperId)
            if paper then
                inv:Remove(paper)
                sendRemoveItemFromContainer(inv, paper)
            end
        end)
    end

    say("mappa \"" .. name .. "\" fabbricata per " .. N.nameOf(player)
        .. ": " .. #(d.ink or {}) .. " tratti, " .. #(d.sym or {}) .. " simboli")
end

local function onCommand(module, command, player, args)
    if module ~= N.MODULE then return end
    if command == N.C_STROKE then onStroke(player, args)
    elseif command == N.C_REMOVE then onRemove(player, args)
    elseif command == N.C_SYNC then onSync(player, args)
    elseif command == N.C_MAKEMAP then onMakeMap(player, args)
    end
end

Events.OnClientCommand.Add(onCommand)

--- Non c'e' un evento di salvataggio da agganciare, e non serve: `save()` gira
--- a ogni modifica, quindi la modData del tempo di gioco e' sempre quella
--- giusta, e a scriverla su disco ci pensa il mondo quando si salva.
---
--- Gli eventi di salvataggio del gioco si guardano prima di usarli - non tutte
--- le build hanno gli stessi - ed e' la ragione per cui qui non ce ne sono:
--- meno cose da guardare, meno cose che possono non esserci.

--- Quanti tratti tiene il deposito, e di chi. Per il pannello di prova, che
--- gira nella stessa macchina virtuale quando si gioca da soli.
function V.census()
    local n, byAuthor = 0, {}
    for _, s in pairs(load()) do
        n = n + 1
        byAuthor[s.author] = (byAuthor[s.author] or 0) + 1
    end
    return n, byAuthor
end

--- Una riga sola all'avvio, ed e' la piu' importante di tutte: dice che
--- questa meta' e' stata caricata. Su un server coop il processo e' un altro,
--- con un log tutto suo, e senza questa riga "non ci sono errori" e "non c'e'
--- nessuno" si scrivono nello stesso modo.
--- QUESTA RIGA NON PASSA DA `say`, ed e' voluto: `say` tace quando la parlantina
--- e' spenta, cioe' sempre in una versione pubblicata, e proprio li' serve
--- sapere che questa meta' e' partita. E' l'unica che si stampa comunque.
print("NW_NetServer: caricato, deposito dei tratti pronto")

--- Il promemoria, e non e' una formalita': la parlantina si accende per un giro
--- di prove e si dimentica accesa per una versione intera. La riga costa niente
--- e sparisce da sola insieme a quello che annuncia.
if V.verbose then
    print("NW_NetServer: PARLANTINA ACCESA - da spegnere prima di pubblicare (V.verbose).")
end

return NW_NetServer
