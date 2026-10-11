--[[ ============================================================================
    NW_NetClient - quello che si spartisce, in partenza e in arrivo.

    Due direzioni, e due depositi diversi che non vanno mai mescolati:

      I MIEI TRATTI stanno dove sono sempre stati, nella modData del giocatore
      (NW_MapDoc). Da soli e' l'unico deposito che esiste, e la mod funziona
      come prima senza sapere niente di questo file. Quando la scelta di
      condivisione non e' "solo io", una copia parte anche per il server.

      I TRATTI DEGLI ALTRI stanno qui, in memoria e basta. Non si salvano: li
      tiene il server, e alla prossima apertura della mappa li rimanda. Salvarli
      vorrebbe dire tenere nel proprio salvataggio il disegno di un altro, che
      poi non si aggiorna piu' e diventa una bugia.

    PERCHE' NON CI SI ACCORGE DI CHI HA DISEGNATO COSA: i tratti degli altri si
    disegnano insieme ai propri, con lo stesso pennello. Chi guarda vede una
    mappa scarabocchiata da piu' mani, che e' il punto.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Net"
require "NeatWriting/NW_Share"
require "NeatWriting/NW_Brush"

NW_NetClient = NW_NetClient or {}
local C = NW_NetClient
local N = NW_Net

--- I tratti degli altri, per id. Vivi finche' dura la sessione.
local remote = {}

--- Mentre si collauda, questa meta' dice cosa le arriva e cosa non parte.
---
--- Serve a distinguere cose che da fuori sono identiche: "il server non ha
--- mandato niente" e "ha mandato qualcosa che non si e' capito"; "il tratto e'
--- partito" e "il tratto e' stato lasciato a casa". Un comando che porta una
--- tabella dentro una tabella e' il posto giusto dove sospettare che qualcosa
--- si perda per strada.
---
--- STA QUI IN CIMA E NON PIU' IN MEZZO AL FILE perche' `shareStroke` la chiama
--- e sta sopra: una `local function` usata prima della sua dichiarazione non e'
--- la locale, e' una globale mai assegnata, cioe' nil - e in Kahlua chiamare
--- nil alza un'eccezione Java che il pcall non prende. Lezione 18 piu' la 33.
---
--- VA SPENTA PRIMA DI PUBBLICARE, come la gemella del server. Da qui pendono
--- tutte le stampe di collaudo della mod - questo file, il pannello di
--- condivisione, il velo di inquadratura, la cartografia, la mappa del morto -
--- quindi questa riga sola le fa tacere tutte insieme, e nessuna va tolta a
--- mano.
---
--- Spenta: la 1.2.1 si pubblica. Si riaccende per un giro di prove, ed e' una
--- parola sola perche' le stampe stanno tutte dietro questa riga - compresa la
--- fotografia dello stato della mappa (NW_Ink.diag), che e' quella che ha
--- chiuso la caccia ai simboli invisibili.
C.verbose = false

local function tell(text)
    if C.verbose then print("NW_NetClient: " .. text) end
end

-- ---------------------------------------------------------------------------
-- In partenza
-- ---------------------------------------------------------------------------

local function send(command, args)
    local player = getSpecificPlayer(0)
    if not player then return end
    sendClientCommand(player, N.MODULE, command, args or {})
end

--- Un tratto appena chiuso se ne va, se c'e' qualcuno con cui spartirlo.
---
--- Il tratto resta comunque nel deposito di casa: questa e' una copia in piu',
--- non un trasloco. Se il server non risponde - o se si sta giocando da soli
--- con la condivisione spenta - non si e' perso niente.
function C.shareStroke(player, stroke)
    if not (player and stroke) then return end
    -- Le tre uscite qui sotto erano mute tutte e tre, e da fuori un tratto che
    -- non parte e' identico a un tratto che parte e non arriva. Sono i tre modi
    -- diversi di non spedire, e vanno distinti: uno e' una scelta, uno e' un
    -- guasto, uno e' un tetto raggiunto.
    if NW_Share.isPrivate(player) then
        tell("non spedito: stai scrivendo solo per te")
        return
    end
    local pts = stroke.pts or stroke.p
    local packed = N.pack(pts)
    if not packed then
        tell("non spedito: punti illeggibili")
        return
    end
    if #packed > N.MAX_POINT_CHARS then
        tell("non spedito: " .. #packed .. " caratteri, il tetto e' " .. N.MAX_POINT_CHARS)
        return
    end

    local share = NW_Share.get(player)
    stroke.nwId = stroke.nwId or N.strokeId(N.nameOf(player))
    send(N.C_STROKE, {
        id = stroke.nwId,
        w = stroke.w,
        c = stroke.c or "black",
        p = packed,
        -- Piatto: nel comando non viaggia nessuna tabella dentro una tabella.
        mode = share.mode,
        players = table.concat(share.players or {}, ","),
    })
end

--- Un tratto cancellato: se era spartito, va tolto anche agli altri.
function C.unshareStroke(player, stroke)
    if not (player and stroke and stroke.nwId) then return end
    send(N.C_REMOVE, { id = stroke.nwId })
end

--- Quello che il server ci ha gia' detto di non poter togliere (e quando), e
--- quando lo abbiamo chiesto l'ultima volta.
local denied = {}
local askedAt = {}

--- Ogni quanto si puo' richiedere lo stesso tratto.
local ASK_MS = 2000

--- Quanto vale un rifiuto. NON PER SEMPRE: il permesso puo' cambiare a partita
--- avviata - un admin che si da' il ruolo con /setaccesslevel, un capo che
--- entra in fazione - e un rifiuto ricordato per tutta la sessione faceva
--- sembrare la gomma rotta proprio a chi adesso il diritto l'aveva
--- (segnalazione 1.0.0, partita ospitata: "non funziona mai, tranne sui miei").
--- Scade dopo questo tempo, e comunque a ogni apertura della mappa del mondo.
local DENY_MS = 30000

--- Cancellare un tratto di un altro: si chiede, e risponde il server. Il
--- permesso non lo decide questa meta' - qui non si sa niente di fazioni e di
--- livelli d'accesso, e va bene cosi'.
---
--- SI CHIEDE UNA VOLTA SOLA. La gomma passa sopra al tratto a ogni fotogramma
--- finche' il tasto e' premuto, e ogni passaggio faceva partire un pacchetto:
--- nel log del server si leggeva una colonna di righe identiche, decine al
--- secondo per un gesto solo. Adesso un rifiuto si ricorda, e nel dubbio non si
--- richiede piu' di una volta ogni due secondi.
function C.removeRemote(id)
    if not id then return end
    local now = getTimestampMs and getTimestampMs() or 0
    if denied[id] and now - denied[id] < DENY_MS then return end
    if askedAt[id] and now - askedAt[id] < ASK_MS then return end
    askedAt[id] = now
    send(N.C_REMOVE, { id = id })
end

--- "Ho aperto la mappa del mondo, dammi quello che posso vedere." E i rifiuti
--- di prima si dimenticano: il permesso potrebbe essere cambiato (DENY_MS).
function C.requestSync()
    remote = {}
    denied = {}
    send(N.C_SYNC, {})
end

--- "Fabbricami questa mappa e mettimela in mano."
---
--- LA FABBRICA STA DI LA', e non e' un giro inutile: un oggetto nato con
--- `instanceItem` da questa parte il server non l'ha mai visto, quindi sparisce
--- al primo riallineamento dell'inventario - e il foglio speso per farlo torna
--- indietro, perche' anche quello lo aveva tolto solo il client. Chi ha aperto
--- il proprio cadavere ha trovato esattamente questo: niente mappa, e la carta
--- ancora li'.
---
--- Il carico viaggia piatto (N.packStrokes, N.packSymbols): tratti e simboli
--- sono liste di tabelle con dentro altre liste, e un comando non le porta.
function C.makeMap(player, kind, x1, y1, x2, y2, name, strokes, symbols, seen, paper)
    if not player then return false end
    local ink = N.packStrokes(strokes)
    local sym = N.packSymbols(symbols)
    tell("chiedo al server una " .. tostring(kind) .. ": "
        .. tostring(ink and #ink or 0) .. " caratteri di tratti, "
        .. tostring(sym and #sym or 0) .. " di simboli")
    send(N.C_MAKEMAP, {
        kind = kind,
        x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        name = name or "",
        ink = ink or "",
        sym = sym or "",
        seen = seen and table.concat(seen, ";") or "",
        paper = paper,
    })
    return true
end

-- ---------------------------------------------------------------------------
-- In arrivo
-- ---------------------------------------------------------------------------

local function absorb(s)
    if type(s) ~= "table" or type(s.p) ~= "string" then return end
    local pts = N.unpack(s.p)
    if not pts then return end
    remote[tostring(s.id)] = {
        id = tostring(s.id),
        author = s.author or "?",
        w = tonumber(s.w) or 3.0,
        c = s.c or "black",
        pts = pts,          -- il nome con cui NW_Brush disegna
        nwRemote = true,
    }
end

local function receive(command, args)
    if command == N.S_ADD then
        local before = C.count()
        absorb(args)
        tell("add: " .. tostring(args and args.author) .. ", punti "
            .. tostring(args and args.p and #args.p or 0) .. " caratteri, "
            .. (C.count() > before and "assorbito" or "SCARTATO"))
    elseif command == N.S_ALL then
        local list = (args and args.strokes) or {}
        local before = C.count()
        for _, s in ipairs(list) do absorb(s) end
        tell("all: " .. tostring(#list) .. " nel pacchetto, "
            .. tostring(C.count() - before) .. " assorbiti")
    elseif command == N.S_GONE then
        if args and args.id then remote[tostring(args.id)] = nil end
    elseif command == N.S_DONE then
        -- Niente da fare: la fine del pacchetto e' un segnale, non un dato.
    elseif command == N.S_DENY then
        -- "Quello non lo puoi togliere": si segna, e per un po' non si
        -- richiede (DENY_MS). Il tratto resta sulla mappa, ed e' giusto che
        -- resti - non e' tuo.
        if args and args.id then
            denied[tostring(args.id)] = getTimestampMs and getTimestampMs() or 0
            tell("negato: " .. tostring(args.id))
        end
    end
end

--- Dalla rete.
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= N.MODULE then return end
    receive(command, args)
end)

--- E da soli, dove OnServerCommand non scatta mai: la meta' server chiama
--- questa direttamente (NW_Net.deliver).
N.setDeliver(function(command, args)
    receive(command, args)
end)

-- ---------------------------------------------------------------------------
-- Per chi disegna
-- ---------------------------------------------------------------------------

--- Quanti tratti altrui abbiamo adesso.
function C.count()
    local n = 0
    for _ in pairs(remote) do n = n + 1 end
    return n
end

--- I tratti degli altri, in una lista che NW_Brush sa disegnare.
---
--- Si ricostruisce a ogni chiamata: sono poche decine di voci e la mappa ne
--- chiede una volta per fotogramma. Tenere una lista in parallelo alla tabella
--- vorrebbe dire tenerle allineate, e non ne vale la pena.
function C.strokes()
    local out = {}
    for _, s in pairs(remote) do out[#out + 1] = s end
    return out
end

--- Il tratto di un altro sotto questo punto del mondo, se c'e'.
--- Serve alla gomma di chi ha il ruolo per cancellarlo.
function C.hit(wx, wy, radius)
    for _, s in pairs(remote) do
        if NW_Brush.hits(s, wx, wy, radius) then return s end
    end
    return nil
end


-- Una riga all'avvio, per la stessa ragione della meta' server: il log deve
-- poter distinguere "tutto bene" da "non caricato".
print("NW_NetClient: caricato")

--- Lo stesso promemoria della meta' server, e per la stessa ragione: da questa
--- riga pende tutto il parlato di collaudo della mod, ed e' la cosa piu' facile
--- da dimenticare accesa.
if C.verbose then
    print("NW_NetClient: PARLANTINA ACCESA - da spegnere prima di pubblicare (C.verbose).")
end

return NW_NetClient
