--[[ ============================================================================
    NW_PlayerStore - la nostra tabella del giocatore, e dove sta davvero.

    Tre cose di Project Writing appartengono al giocatore e non a un oggetto:
    i tratti sulla mappa del mondo (NW_MapDoc, `worldInk`), i simboli travasati
    da una mappa trovata che aspettano la mappa del mondo (NW_Cartography,
    `pendingSym`) e i volantini letti (NW_Media, `media`).

    IN SINGLE PLAYER stanno nella modData del personaggio, come sempre: si
    salvano col salvataggio e la rete non c'entra.

    IN MULTIPLAYER NO. La modData del giocatore e' una tabella sola, e il gioco
    la spedisce INTERA al server ogni volta che qualcuno chiama transmitModData
    - vanilla lo fa a ogni cambio della barra rapida (ISHotbar:savePosition),
    piu' volte per ogni capo che si toglie o si mette. Un disegno sulla mappa del
    mondo arriva a 150 KB (NW_MapDoc.MAX_WORLD): partiva tutto, ogni volta,
    anche per un cambio di cintura. E' lo stesso carico che e' stato segnalato
    per NeatUI Equipment su un server dedicato, e chi ha tutte e due le mod lo
    pagava due volte.

    Quindi in rete la tabella sta in un file del client, in Zomboid/Lua, uno per
    personaggio, e nella modData resta solo `nwid`: pochi caratteri che dicono
    quale file e' di questo personaggio. Quello che c'era nella modData da una
    versione precedente passa nel file alla prima lettura, e la modData si
    svuota con un'ultima spedizione.

    IL FILE SI CHIAMA COL SOLO `nwid` (ProjectWriting_<nwid>.txt). Nella 1.0.0
    davanti c'era anche l'indirizzo del server, e non aggiungeva niente: `nwid`
    e' gia' unico (millisecondi, un numero a caso e il nome utente). Toglieva
    invece qualcosa: lo stesso server raggiunto per nome invece che per numero,
    o con l'indirizzo cambiato dal provider, dava un altro file, e il disegno
    sembrava sparito. Il file col nome della 1.0.0 si cerca ancora, una volta,
    e si ricopia sotto il nome nuovo.

    I TRATTI SPARTITI NON C'ENTRANO: quelli il server li tiene nel suo deposito
    (NW_NetServer, nella modData del mondo), e da li' tornano a chi li puo'
    vedere. Qui sta solo la copia personale.
============================================================================ ]]--

if isServer() then return end

NW_PlayerStore = NW_PlayerStore or {}
local S = NW_PlayerStore

local KEY         = "NeatWriting"
local FILE_PREFIX = "ProjectWriting_"
local FILE_MAGIC  = "NW-PLAYER 1"
local NEWLINE     = string.char(10)

-- ---------------------------------------------------------------------------
-- Testo
-- ---------------------------------------------------------------------------
-- Le cifre esadecimali a mano: string.format("%X") in Kahlua non e' garantito,
-- e un errore qui costerebbe il disegno.
local HEX = "0123456789ABCDEF"
local function esc(s)
    return (string.gsub(s, "[^%w _%-%.]", function(c)
        local b = string.byte(c)
        local hi, lo = math.floor(b / 16), b % 16
        return "%" .. string.sub(HEX, hi + 1, hi + 1) .. string.sub(HEX, lo + 1, lo + 1)
    end))
end

local function unesc(s)
    return (string.gsub(s, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local encode
encode = function(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. esc(v) .. ";"
    elseif t == "number" then
        out[#out + 1] = "n" .. tostring(v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "b1;" or "b0;"
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            local tk, tv = type(k), type(val)
            if (tk == "string" or tk == "number")
                and (tv == "string" or tv == "number" or tv == "boolean" or tv == "table") then
                encode(k, out)
                encode(val, out)
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "b0;"
    end
end

--- Un testo malformato da' nil, mai un errore.
local decode
decode = function(s, i)
    local tag = string.sub(s, i, i)
    if tag == "{" then
        local t = {}
        i = i + 1
        while string.sub(s, i, i) ~= "}" do
            if i > #s then return nil, i end
            local k, v
            k, i = decode(s, i)
            if k == nil then return nil, i end
            v, i = decode(s, i)
            if v == nil then return nil, i end
            t[k] = v
        end
        return t, i + 1
    end
    local stop = string.find(s, ";", i, true)
    if not stop then return nil, #s + 1 end
    local body = string.sub(s, i + 1, stop - 1)
    if tag == "s" then return unesc(body), stop + 1 end
    if tag == "n" then return tonumber(body), stop + 1 end
    if tag == "b" then return body == "1", stop + 1 end
    return nil, stop + 1
end

S._encode = function(v) local out = {} encode(v, out) return table.concat(out) end
S._decode = function(s) return (decode(s, 1)) end

-- ---------------------------------------------------------------------------
-- File
-- ---------------------------------------------------------------------------

local function safeName(s)
    return (string.gsub(tostring(s or ""), "[^%w_%-]", "_"))
end

--- Il server come lo nominava la 1.0.0 nel nome del file: serve solo a
--- ritrovare quei file (fileEntry).
local function serverKey()
    local ip, port = "", ""
    pcall(function() ip = tostring(getServerIP() or "") end)
    pcall(function() port = tostring(getServerPort() or "") end)
    return safeName(ip .. "_" .. port)
end

local function readFile(name)
    local reader = getFileReader(name, false)
    if not reader then return nil end
    local data = nil
    if reader:readLine() == FILE_MAGIC then
        local line = reader:readLine()
        if line and line ~= "" then
            local ok, t = pcall(function() return (decode(line, 1)) end)
            if ok and type(t) == "table" then data = t end
        end
    end
    reader:close()
    return data
end

local function writeFile(name, data)
    local writer = getFileWriter(name, true, false)
    if not writer then return false end
    local out = {}
    encode(data, out)
    writer:write(FILE_MAGIC .. NEWLINE .. table.concat(out) .. NEWLINE)
    writer:close()
    return true
end

-- ---------------------------------------------------------------------------
-- La tabella
-- ---------------------------------------------------------------------------

local files = {}   -- [nome file] = { name = ..., data = tabella }

-- `nwid` di ogni personaggio visto in questa sessione, per oggetto giocatore
-- (un personaggio nuovo dopo la morte e' un altro oggetto, e un altro id).
-- Se la modData lo perde a meta' partita - una copia rimandata dal server prima
-- che la nostra spedizione arrivasse - si rimette questo invece di inventarne
-- un secondo, che spezzerebbe il disegno in due file.
local known = {}

local function modData(player)
    local md
    pcall(function() md = player:getModData() end)
    return md
end

--[[ LA SPEDIZIONE ASPETTA CHE IL PERSONAGGIO SIA NEL MONDO.

    IsoObject.transmitModData esce senza dire niente se il personaggio non ha
    ancora una casella (`square`, letto nel bytecode), e la casella arriva al
    suo primo aggiornamento dopo che la mappa intorno e' stata costruita - cioe'
    DOPO OnCreatePlayer (lezione 78). Ed e' proprio in OnCreatePlayer che
    NW_Media chiede la tabella per la prima volta: un `nwid` nato li' restava
    solo sul client, al rientro il server non lo conosceva e ne nasceva un
    altro, con un file vuoto - il disegno sembrava sparito.

    Quindi, senza casella, la spedizione si segna e parte da OnTick appena la
    casella c'e' da due fotogrammi (il primo e' quello in cui il motore la
    copia in `square`). Senza niente in attesa OnTick guarda una tabella vuota.
]]
local waiting = {}   -- [giocatore] = fotogrammi passati con la casella

local function hasSquare(player)
    local sq
    pcall(function() sq = player:getCurrentSquare() end)
    return sq ~= nil
end

local function transmit(player)
    if hasSquare(player) then
        pcall(function() player:transmitModData() end)
        waiting[player] = nil
    else
        waiting[player] = 0
    end
end

--- Prima si guarda, poi si cambia: le tabelle di Kahlua sono mappe Java, e
--- toccarne le chiavi mentre le si scorre non e' una cosa da fare.
local function sendWaiting()
    local ready, later = nil, nil
    for player, ticks in pairs(waiting) do
        if hasSquare(player) then
            if ticks >= 1 then
                ready = ready or {}
                ready[#ready + 1] = player
            else
                later = later or {}
                later[#later + 1] = player
            end
        end
    end
    for _, player in ipairs(later or {}) do waiting[player] = 1 end
    for _, player in ipairs(ready or {}) do
        waiting[player] = nil
        pcall(function() player:transmitModData() end)
    end
end

Events.OnTick.Add(sendWaiting)

--- Vero se la tabella non ha nemmeno una chiave.
---
--- NON CON `next`, CHE IN KAHLUA NON ESISTE. Le funzioni di base del gioco
--- sono quelle della BaseLib di Kahlua piu' lo stdlib.lua nella cartella di
--- installazione, e `next` non sta in nessuna delle due (lezione 79). Con
--- `next` qui, la 1.0.0 dava "Object tried to call nil in root" alla prima
--- apertura della mappa del mondo in rete; da soli questa riga non si
--- raggiunge mai, ed e' per questo che in prova non si era visto.
local function isEmpty(t)
    for _ in pairs(t) do return false end
    return true
end

--- In rete: il file del personaggio, letto e migrato alla prima richiesta.
local function fileEntry(player, md)
    if type(md.nwid) ~= "string" or md.nwid == "" then
        local id = known[player]
        if not id then
            local name = "x"
            pcall(function() name = player:getUsername() or name end)
            id = safeName(tostring(getTimestampMs()) .. "_" .. tostring(ZombRand(1000000)) .. "_" .. name)
        end
        md.nwid = id
        transmit(player)
    end
    known[player] = md.nwid

    local fileName = FILE_PREFIX .. md.nwid .. ".txt"
    local entry = files[fileName]
    if entry then return entry end

    local data = readFile(fileName)
    if not data then
        -- Il nome della 1.0.0, con l'indirizzo del server davanti: se c'e', si
        -- ricopia sotto il nome nuovo e da li' in poi vale quello.
        data = readFile(FILE_PREFIX .. serverKey() .. "_" .. md.nwid .. ".txt")
        if data then writeFile(fileName, data) end
    end
    entry = { name = fileName, data = data or {} }
    files[fileName] = entry

    -- Quello che una versione precedente aveva lasciato nella modData: nel
    -- file, una chiave per volta senza sovrascrivere quello che il file ha gia',
    -- e poi la modData si alleggerisce una volta per tutte.
    local old = md[KEY]
    if type(old) == "table" then
        for k, v in pairs(old) do
            if entry.data[k] == nil then entry.data[k] = v end
        end
        md[KEY] = nil
        writeFile(fileName, entry.data)
        transmit(player)
    end
    return entry
end

--- La tabella NeatWriting del giocatore, creata se `create`. Sempre la stessa
--- tabella viva: chi la cambia poi chiama S.persist.
function S.root(player, create)
    if not player then return nil end
    local md = modData(player)
    if not md then return nil end

    if isClient() then
        local entry = fileEntry(player, md)
        if not create and entry.data.v == nil and isEmpty(entry.data) then return nil end
        return entry.data
    end

    local d = md[KEY]
    if type(d) ~= "table" then
        if not create then return nil end
        d = {}
        md[KEY] = d
    end
    return d
end

--- Rende definitiva una modifica. In rete riscrive il file e basta: niente
--- transmitModData, che era il carico. Da soli non serve niente, la modData e'
--- gia' quella che si salva.
function S.persist(player)
    if not player or not isClient() then return end
    local md = modData(player)
    if not md then return end
    local entry = fileEntry(player, md)
    pcall(function() writeFile(entry.name, entry.data) end)
end

--- Vero se la tabella del giocatore sta in un file e non nella modData.
function S.isFileBacked()
    return isClient() == true
end

return S
