--[[ ============================================================================
    NW_Media - i volantini letti, che in rete il gioco si dimentica.

    IL BUCO E' DI VANILLA, ED E' MISURATO. Quando si finisce di leggere una
    brochure, `ISReadABook` chiama `character:addReadPrintMedia(id)`, e da quel
    momento la mappa del mondo mostra l'icona del volantino sul posto da cui
    parla (`ISWorldMap:renderPrintMedia`, che legge `getReadPrintMedia`).

    Quell'insieme il personaggio se lo SALVA - `IsoGameCharacter.save` e `load`
    lo scrivono e lo rileggono - ma non lo SPEDISCE: il pacchetto che sincronizza
    i campi del personaggio (`SyncPlayerFieldsPacket`) porta ricette, tratti,
    libri letti, ferite, lettura in corso e fitness, e i volantini non ci sono.
    In singleplayer il salvataggio e' quello locale e tutto torna; in rete il
    personaggio lo salva il SERVER, da una copia che quella riga non l'ha mai
    ricevuta. Si rientra, l'insieme e' vuoto, e sulla mappa non c'e' piu' niente
    da premere.

    QUI SI TIENE UNA COPIA NOSTRA, nella tabella del giocatore (NW_PlayerStore):
    da soli nella modData, in rete in un file del client. Non si inventa niente: si rimettono al
    personaggio gli id che aveva gia' letto, con la sua stessa funzione. Chi non
    ha letto un volantino non ne vede comparire nessuno.

    TRE MOMENTI, e nessuno di piu':
      * quando il personaggio nasce o entra   -> si rimette quello che sapeva
      * quando si finisce di leggere qualcosa -> si segna
      * quando si apre la mappa del mondo     -> cintura, per i due casi di cui
                                                 sopra che fossero saltati

    SI SCRIVE SOLO SE LA LISTA E' CAMBIATA: a ogni apertura della mappa
    sarebbe una scrittura per una lista che quasi sempre e' identica a prima.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Config"
require "NeatWriting/NW_PlayerStore"
require "TimedActions/ISReadABook"

NW_Media = NW_Media or {}
local M = NW_Media

--- La nostra tabella dentro la modData del giocatore.
local function docOf(player)
    return NW_PlayerStore.root(player, true)
end

--- Gli id che il personaggio dice di aver letto adesso.
---
--- `getReadPrintMedia` torna un insieme Java: si travasa in una ArrayList e la
--- si scorre per indice, che e' la strada che prende vanilla stessa in
--- ISWorldMap:renderPrintMedia.
local function readNow(player)
    local out = {}
    pcall(function()
        local set = player:getReadPrintMedia()
        if not set then return end
        local list = ArrayList.new(set)
        for i = 1, list:size() do
            local id = list:get(i - 1)
            if id then out[#out + 1] = tostring(id) end
        end
    end)
    return out
end

--- Rimette quello che il personaggio aveva letto, e segna quello che ha letto
--- da allora. Le due cose stanno insieme perche' sono la stessa passata sulla
--- stessa lista, e separarle vorrebbe dire scorrerla due volte.
function M.sync(player)
    if not player then return end
    local d = docOf(player)
    if not d then return end
    local saved = type(d.media) == "table" and d.media or {}

    -- Quello che il personaggio sa adesso.
    local seen = {}
    for _, id in ipairs(readNow(player)) do seen[id] = true end

    -- Quello che sapeva e non sa piu': glielo si rimette.
    for _, id in ipairs(saved) do
        if not seen[id] then
            pcall(function() player:addReadPrintMedia(id) end)
            seen[id] = true
        end
    end

    -- E la lista nuova, nell'ordine in cui e' arrivata: prima i vecchi, poi i
    -- letti da poco.
    local out, dentro = {}, {}
    for _, id in ipairs(saved) do
        if not dentro[id] then
            dentro[id] = true
            out[#out + 1] = id
        end
    end
    for _, id in ipairs(readNow(player)) do
        if not dentro[id] then
            dentro[id] = true
            out[#out + 1] = id
        end
    end

    if #out == 0 then
        d.media = nil
    else
        d.media = out
    end

    -- Solo se e' cambiata davvero: vedi la nota in cima.
    if #out ~= #saved then
        NW_PlayerStore.persist(player)
    end
end

-- ---------------------------------------------------------------------------
-- I tre momenti
-- ---------------------------------------------------------------------------

Events.OnCreatePlayer.Add(function(_, player)
    pcall(function() M.sync(player) end)
end)

--- Finito di leggere.
---
--- VANILLA SEGNA IL VOLANTINO IN `complete`, NON IN `perform`
--- (ISReadABook.lua, 42.21). E `complete` in rete gira sul SERVER: il client
--- non lo viene mai a sapere, il suo insieme resta vuoto, e la mappa del mondo
--- - che legge quello del client - non ha nessuna icona da mostrare, nemmeno
--- premendo il tasto (segnalazione 42.21). In single player le due funzioni
--- girano qui una dopo l'altra, perform prima (lezione 71), quindi anche li'
--- la nostra copia restava indietro di un volantino fino all'apertura della
--- mappa.
---
--- Quindi il volantino lo segniamo noi, sul client, prima di aggiornare la
--- copia: e' lo stesso id che vanilla scrivera' dall'altra parte, letto dallo
--- stesso posto (`item:getModData().printMedia.id`).
if ISReadABook and ISReadABook.perform then
    ISReadABook.perform_prepatch_neatwriting = ISReadABook.perform
    function ISReadABook:perform()
        self:perform_prepatch_neatwriting()
        pcall(function()
            local item = self.item
            local md = item and item:hasModData() and item:getModData()
            local pm = md and md.printMedia
            if pm and pm.id then self.character:addReadPrintMedia(pm.id) end
        end)
        pcall(function() M.sync(self.character) end)
    end
end

return NW_Media
