--[[ ============================================================================
    NW_Net - il vocabolario che le due meta' parlano.

    Sta in shared perche' lo leggono tutti e due: il client che spedisce
    (NW_NetClient) e il server che riceve, conserva e ridistribuisce
    (NW_NetServer). Qui dentro non c'e' logica di gioco, solo il modo di dirsi
    le cose: come si chiamano i comandi, come viaggia un tratto, e quanto grande
    puo' essere prima che il server lo rifiuti.

    SERVE SOLO ALLA MAPPA DEL MONDO. Una mappa di carta e' un oggetto, e il suo
    disegno viaggia da se' con la modData dell'oggetto (NW_MapDoc): li' non c'e'
    niente da spartire, perche' la mappa passa di mano intera. La mappa del
    mondo invece non e' di nessuno, e quello che ci si disegna sopra e' del
    giocatore che lo ha fatto: per farlo vedere a un altro ci vuole il server.

    DUE COSE CHE NON SI INDOVINANO, lette nei sorgenti di PZShareMapNotes e poi
    verificate:

    1. IN SINGLEPLAYER `sendServerCommand` NON ARRIVA AL CLIENT. Tutt'e due gli
       overload stanno dentro `if (GameServer.server)`, che da soli e' falso, e
       niente le inoltra a SinglePlayerServer. `sendClientCommand` invece
       funziona: LuaManager lo fa girare per SinglePlayerClient e fa scattare
       OnClientCommand. Percio' la meta' server, quando e' sola, consegna in
       casa con una chiamata di funzione (NW_Net.deliver), che il client
       registra all'avvio. Senza, si disegna, il server accetta, salva, e non
       rimanda mai niente: il tratto sparisce appena si molla il mouse.

    2. I PUNTI VIAGGIANO IN UNA STRINGA. Una tabella dentro una tabella dentro
       un comando e' esattamente il tipo di annidamento che il serializzatore
       del gioco lascia per strada senza dire niente. "x1,y1;x2,y2" e' un
       valore solo, e costa anche meno byte di un array di numeri.
============================================================================ ]]--

NW_Net = NW_Net or {}
local N = NW_Net

--- Il modulo con cui si firmano i comandi: ci arrivano quelli di tutte le mod,
--- e chi non e' nostro si scarta subito.
N.MODULE = "NeatWriting"

-- ---------------------------------------------------------------------------
-- I comandi
-- ---------------------------------------------------------------------------

-- Dal client al server.
N.C_STROKE = "stroke"     -- ho disegnato questo
N.C_REMOVE = "unstroke"   -- ho cancellato questo (mio)
N.C_SYNC   = "sync"       -- ho aperto la mappa: dammi quello che posso vedere
N.C_MAKEMAP = "makemap"   -- fabbricami questa mappa e mettimela in mano

-- Dal server al client.
N.S_ADD  = "add"          -- un tratto nuovo di qualcun altro
N.S_GONE = "gone"         -- un tratto non c'e' piu'
N.S_ALL  = "all"          -- un blocco di tratti, in risposta a una sync
N.S_DONE = "done"         -- la sync e' finita (serve al pannello di prova)
N.S_DENY = "deny"         -- quel tratto non lo puoi togliere

-- ---------------------------------------------------------------------------
-- I limiti
-- ---------------------------------------------------------------------------
--
-- Misurati, non copiati: `strumenti/controlli/peso-tratti.js` dice che un
-- tratto sottile e mosso sta in 8,7 KB e che ce ne vogliono 239 per riempire da
-- soli i 2 MB di un oggetto del giocatore. Qui il deposito e' del mondo, non di
-- un oggetto, ma la prudenza e' la stessa: un tetto per autore e uno per
-- tratto, perche' il caso peggiore non lo faccia una persona sola.
N.MAX_POINTS_PER_STROKE = 600
N.MAX_STROKES_PER_AUTHOR = 60
N.MAX_STROKES_TOTAL = 400
N.MAX_POINT_CHARS = N.MAX_POINTS_PER_STROKE * 24   -- prima di leggere, non dopo

--- Quanti tratti in un blocco di sincronizzazione.
---
--- Erano dodici, ed erano troppi: un tratto fitto sta in 14 KB di punti, e
--- dodici in un comando solo fanno un pacchetto da 170 KB. Un comando di rete
--- non e' un canale: e' un messaggio, e i messaggi grossi sono la ragione per
--- cui le mod da disegno si prendono la fama di rompere i server. Quattro per
--- volta fanno tre giri invece di uno e nessun messaggio sopra i 60 KB.
N.SYNC_BATCH = 4

-- ---------------------------------------------------------------------------
-- Da soli o in compagnia
-- ---------------------------------------------------------------------------

--- Vero solo in singleplayer: ne' client ne' server, le due meta' nella stessa
--- macchina virtuale.
function N.isSolo()
    return not isClient() and not isServer()
end

--- Il disegno a mano libera e' permesso? Lo decide la partita, non il giocatore:
--- e' un'opzione sandbox (media/sandbox-options.txt), e in rete i SandboxVars
--- arrivano dal server a tutti i client.
---
--- SPENTO SI SPEGNE TUTTO IL GESTO, non il disegno: niente tasto della penna nel
--- pannello, niente tratto al clic, e il server rifiuta quelli che arrivano lo
--- stesso da un client che non lo sa. I tratti gia' fatti restano e si possono
--- cancellare - buttare il lavoro di qualcuno perche' un admin ha cambiato
--- idea non e' una regola, e' un dispetto.
---
--- Sta qui perche' lo leggono tutte e due le meta', e si chiede ogni volta: un
--- admin puo' cambiare le opzioni sandbox a partita avviata.
function N.freehandAllowed()
    local sv = SandboxVars and SandboxVars.ProjectWriting
    return not (sv and sv.Freehand == false)
end

--- La partita lascia la mappa al gioco? E' la stessa scelta di "Lascia la mappa
--- al gioco" fra le opzioni della mod, ma presa per tutti: un server costruito
--- sulla mappa di vanilla e sulla sua condivisione non deve dipendere da cosa
--- ha spuntato ogni singolo giocatore. Accesa vince sull'opzione personale;
--- spenta decide ognuno per se', come prima.
---
--- Tocca la mappa del mondo e le mappe di carta, non i fogli: si scrive sui
--- diari come sempre, e i pacchetti di simboli restano.
function N.vanillaMapForced()
    local sv = SandboxVars and SandboxVars.ProjectWriting
    return sv ~= nil and sv.VanillaMap == true
end

--- Come si chiama chi gioca qui. In rete e' il nome utente; da soli non c'e' un
--- nome utente vero, e "solo" va benissimo: il deposito e' suo e basta.
function N.nameOf(player)
    if not player then return nil end
    local name
    pcall(function() name = player:getUsername() end)
    if name and name ~= "" then return name end
    return "solo"
end

-- ---------------------------------------------------------------------------
-- I punti, in una stringa
-- ---------------------------------------------------------------------------

--- Da array piatto {x1,y1,x2,y2,...} a "x1,y1;x2,y2;...".
--- I decimali si tagliano a due: sono quadrati di mondo, e un centesimo di
--- quadrato e' molto meno di un pixel a qualunque zoom.
function N.pack(pts)
    if type(pts) ~= "table" then return nil end
    local n = #pts / 2
    if n < 2 then return nil end
    local parts = {}
    for i = 1, n do
        parts[i] = string.format("%.2f,%.2f", pts[i * 2 - 1], pts[i * 2])
    end
    return table.concat(parts, ";")
end

--- E ritorno. Si legge un punto oltre il tetto e poi si smette: cosi' un
--- messaggio malfatto non fa costruire una tabella grande quanto vuole lui, e
--- chi controlla vede lo stesso che era troppo lungo invece di riceverlo
--- tagliato e crederlo buono.
function N.unpack(data)
    if type(data) ~= "string" then return nil end
    local pts = {}
    local limit = (N.MAX_POINTS_PER_STROKE + 1) * 2
    for pair in string.gmatch(data, "[^;]+") do
        if #pts >= limit then break end
        local x, y = string.match(pair, "([^,]+),([^,]+)")
        x, y = tonumber(x), tonumber(y)
        if x and y then
            pts[#pts + 1] = x
            pts[#pts + 1] = y
        end
    end
    if #pts < 4 then return nil end
    return pts
end

-- ---------------------------------------------------------------------------
-- Il carico di una mappa fabbricata
-- ---------------------------------------------------------------------------
--
-- UNA MAPPA INTERA IN DUE STRINGHE, e non e' un vezzo. Un comando di rete non
-- puo' portare una tabella dentro una tabella dentro una tabella - i tratti
-- sono una lista di tratti, e ogni tratto ha una lista di punti: tre livelli, e
-- il serializzatore del gioco li lascia per strada senza dire niente. La stessa
-- ragione per cui i punti viaggiano gia' in stringa da soli.
--
-- Un tratto:  spessore | inchiostro | punti impacchettati        separati da `|`
-- I tratti:   uno dopo l'altro                                   separati da `~`
-- Un simbolo: tipo | id | x | y | r | g | b | a | scala | ax | ay | rotazione
-- I simboli:  uno dopo l'altro                                   separati da `~`
--
-- Il separatore e' `~` perche' `;` e `,` sono gia' presi dai punti e `|` dai
-- campi: un carattere che compare dentro un campo spezzerebbe la riga in un
-- punto sbagliato, e un biglietto di testo puo' contenere quasi tutto.

local FIELD, ROW = "|", "~"

--- Una lista di tratti in una stringa sola. `nil` se non c'e' niente da dire.
function N.packStrokes(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local rows = {}
    for _, s in ipairs(list) do
        local packed = N.pack(s.p or s.pts)
        if packed then
            rows[#rows + 1] = table.concat(
                { tostring(s.w or 3.0), tostring(s.c or "black"), packed }, FIELD)
        end
    end
    if #rows == 0 then return nil end
    return table.concat(rows, ROW)
end

function N.unpackStrokes(data)
    if type(data) ~= "string" or data == "" then return nil end
    local out = {}
    for row in string.gmatch(data, "[^" .. ROW .. "]+") do
        local w, c, pts = string.match(row, "([^|]*)|([^|]*)|(.+)")
        local p = pts and N.unpack(pts) or nil
        if p then
            out[#out + 1] = { w = tonumber(w) or 3.0, c = c ~= "" and c or "black", p = p }
        end
    end
    if #out == 0 then return nil end
    return out
end

--- I simboli di vanilla nella forma che NW_MapDoc sa rimettere a posto.
---
--- Il testo di un biglietto e' l'ultimo campo e non si spezza: puo' contenere
--- spazi, punteggiatura e accenti, e leggerlo per ultimo vuol dire che quello
--- che resta della riga e' tutto testo, comunque sia fatto.
function N.packSymbols(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local rows = {}
    for _, e in ipairs(list) do
        rows[#rows + 1] = table.concat({
            tostring(e.t or "tex"),
            tostring(e.x or 0), tostring(e.y or 0),
            tostring(e.r or 0), tostring(e.g or 0), tostring(e.b or 0),
            tostring(e.a or 1), tostring(e.s or 1),
            tostring(e.ax or 0.5), tostring(e.ay or 0.5),
            tostring(e.rot or 0),
            -- Il separatore di riga non puo' stare dentro un campo, e il testo
            -- di un biglietto e' l'unico campo che il giocatore scrive: una
            -- tilde diventa un trattino. E' l'unico carattere che si perde, e
            -- si perde in modo visibile invece di spezzare la mappa in due.
            (tostring(e.id or ""):gsub(ROW, "-")),
        }, FIELD)
    end
    return table.concat(rows, ROW)
end

function N.unpackSymbols(data)
    if type(data) ~= "string" or data == "" then return nil end
    local out = {}
    for row in string.gmatch(data, "[^" .. ROW .. "]+") do
        -- Undici campi e poi TUTTO IL RESTO. Spezzare anche l'ultimo sulle
        -- barre taglierebbe a meta' un biglietto che ne contiene una - e un
        -- biglietto puo' contenere qualunque cosa, e' testo scritto a mano.
        local f = { string.match(row,
            "^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$") }
        if #f >= 12 then
            -- L'id e' l'ultimo: per un simbolo e' un nome, per un biglietto e'
            -- quello che ci hai scritto dentro.
            local id = f[12]
            if id ~= "" then
                out[#out + 1] = {
                    t = f[1] == "txt" and "txt" or "tex",
                    x = tonumber(f[2]) or 0, y = tonumber(f[3]) or 0,
                    r = tonumber(f[4]) or 0, g = tonumber(f[5]) or 0,
                    b = tonumber(f[6]) or 0, a = tonumber(f[7]) or 1,
                    s = tonumber(f[8]) or 1,
                    ax = tonumber(f[9]) or 0.5, ay = tonumber(f[10]) or 0.5,
                    rot = tonumber(f[11]) or 0,
                    id = id,
                }
            end
        end
    end
    if #out == 0 then return nil end
    return out
end

--- Un nome che non si ripete: chi l'ha fatto, quando, e un numero a caso per
--- due tratti chiusi nello stesso millisecondo.
function N.strokeId(author)
    local t = getTimestampMs and getTimestampMs() or 0
    return tostring(author) .. "_" .. tostring(t) .. "_" .. tostring(ZombRand(100000))
end

--- Una copia, come se fosse passata dalla rete.
---
--- Da soli le due meta' si passano la stessa tabella, e chi riceve la modifica
--- (i punti si aprono in array) starebbe scrivendo dentro il deposito del
--- server. Copiare tiene onesto quel confine anche dove non c'e'.
function N.copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = N.copy(v) end
    return out
end

-- ---------------------------------------------------------------------------
-- La consegna in casa
-- ---------------------------------------------------------------------------

--- La meta' client si registra qui all'avvio; la meta' server chiama questa
--- quando e' sola. In rete non serve a nessuno: li' i comandi passano davvero
--- per il filo.
N.deliver = nil

function N.setDeliver(fn)
    N.deliver = fn
end

return NW_Net
