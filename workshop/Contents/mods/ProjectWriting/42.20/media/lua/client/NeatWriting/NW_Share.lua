--[[ ============================================================================
    NW_Share - con chi sto scrivendo.

    Una scelta sola, che resta accesa. Si mette una volta - "fazione" - e da li'
    in poi ogni segno nuovo e' della fazione: il simbolo, il biglietto di testo
    e il tratto a mano libera. Si chiude la mappa, si esce dal gioco, si torna
    il giorno dopo e si sta ancora scrivendo per la fazione. Per tornare privati
    si rimette **solo io**.

    Non e' una finestra da riaprire ogni volta, ed e' la differenza fra una
    funzione che si usa e una che si prova una volta: il pannello di vanilla
    chiede la condivisione UNA ANNOTAZIONE ALLA VOLTA, dopo averla posata, ed e'
    il motivo per cui in rete quasi nessuno la usa.

    LE CINQUE SCELTE SONO QUELLE DI VANILLA, e non se ne inventano altre: e' il
    server a decidere chi vede cosa, e gli si parla nella sua lingua
    (`symbol:setSharing`).

    DOVE STA: nella modData del giocatore, che in rete si spedisce da se' con
    transmitModData. Non e' un file di preferenze perche' non e' una preferenza:
    e' roba della partita, e in rete deve arrivare anche al server.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Config"

NW_Share = NW_Share or {}
local S = NW_Share

local KEY = "NW_share"

--- Le cinque, nell'ordine in cui si leggono.
S.MODES = { "private", "faction", "safehouse", "players", "all" }

--- Come si chiamano, nella lingua di chi gioca.
S.LABELS = {
    private   = "IGUI_NW_ShareOnlyMe",
    faction   = "IGUI_NW_ShareFaction",
    safehouse = "IGUI_NW_ShareSafehouse",
    players   = "IGUI_NW_SharePlayers",
    all       = "IGUI_NW_ShareEveryone",
}

local function fresh()
    return { mode = "private", players = {} }
end

local function clean(raw)
    if type(raw) ~= "table" then return nil end
    local ok = false
    for _, m in ipairs(S.MODES) do if raw.mode == m then ok = true break end end
    if not ok then return nil end
    local players = {}
    if type(raw.players) == "table" then
        for _, name in ipairs(raw.players) do
            if type(name) == "string" and name ~= "" then players[#players + 1] = name end
        end
    end
    return { mode = raw.mode, players = players }
end

--- La scelta di questo giocatore. Mai nil: chi non ha mai scelto e' privato.
---
--- CON LA CONDIVISIONE SPENTA RISPONDE SEMPRE "solo io", ed e' qui che va
--- messo il freno e non nei tre posti che spediscono. Da questa funzione
--- passano tutti: `applyTo` per i simboli e i biglietti di vanilla,
--- `isPrivate` per i tratti a mano libera, `label` per il tooltip. Spegnerla
--- qui vuol dire che non parte niente, e non c'e' un quarto posto che domani
--- ci si dimentica di controllare.
---
--- La scelta salvata NON si tocca: riaccendendo l'opzione si ritrova quella di
--- prima invece di ricominciare da capo.
function S.get(player)
    if not player then return fresh() end
    if NW.sharing and not NW.sharing() then return fresh() end
    local md
    pcall(function() md = player:getModData() end)
    if not md then return fresh() end
    return clean(md[KEY]) or fresh()
end

--- Cambia la scelta, e in rete la manda.
function S.set(player, mode, players)
    if not player then return end
    -- 'next' e' una funzione di Lua: chiamare cosi' una locale la coprirebbe
    -- dentro questa funzione, e prima o poi qualcuno ci scrive un pairs.
    local chosen = clean({ mode = mode, players = players }) or fresh()
    -- Il proprio nome non sta nella lista di chi puo' leggere: i propri segni
    -- si vedono comunque, e' la prima riga di `visibleTo` sul server. Si toglie
    -- QUI e non solo dal disegno del pannello, perche' una voce che si vede
    -- solo nel conteggio - "giocatori scelti (1)" con la lista vuota - non si
    -- puo' piu' togliere da nessuna parte.
    local me
    pcall(function() me = player:getUsername() end)
    if me and me ~= "" then
        local keep = {}
        for _, name in ipairs(chosen.players) do
            if name ~= me then keep[#keep + 1] = name end
        end
        chosen.players = keep
    end
    local md
    pcall(function() md = player:getModData() end)
    if not md then return end
    md[KEY] = chosen
    if isClient() then pcall(function() player:transmitModData() end) end
    -- In prova serve sapere se la scelta e' stata fatta o e' rimasta quella di
    -- prima: il pannello non lascia nessun'altra traccia nel log, e un tratto
    -- che arriva al server "privato" non dice se il pannello non ha funzionato
    -- o se semplicemente nessuno l'ha toccato. Passa da qui anche il banco di
    -- prova, quindi la riga vale per tutti e due i modi di scegliere.
    if NW_NetClient and NW_NetClient.verbose then
        local how = chosen.mode
        if how == "players" then how = how .. " (" .. tostring(#chosen.players) .. ")" end
        print("NW_Share: ora scrivi per " .. how)
    end
    return chosen
end

--- Vero quando quello che si disegna resta a chi lo disegna.
function S.isPrivate(player)
    return S.get(player).mode == "private"
end

--- Come si chiama la scelta attiva, da mettere su un tasto o in un tooltip.
---
--- Con "questi giocatori" ci si mette anche quanti sono, perche' la stessa
--- scelta puo' voler dire nessuno o mezzo server, e chi legge il tooltip sta
--- chiedendo proprio quello.
function S.label(player)
    local p = S.get(player)
    local name = getText(S.LABELS[p.mode] or "") or p.mode
    if p.mode == "players" then
        return name .. " (" .. tostring(#p.players) .. ")"
    end
    return name
end

-- ---------------------------------------------------------------------------
-- Verso vanilla
-- ---------------------------------------------------------------------------

--- La stessa scelta, nella forma che vuole `symbol:setSharing`.
---
--- nil vuol dire privata, ed e' quello che vanilla si aspetta: non una tabella
--- con tutto spento, proprio niente.
function S.vanilla(player)
    local p = S.get(player)
    if p.mode == "private" then return nil end
    if p.mode == "all" then return { everyone = true } end
    return {
        everyone = false,
        faction = p.mode == "faction",
        safehouse = p.mode == "safehouse",
        players = p.mode == "players" and p.players or {},
    }
end

--- Applica la scelta a un'annotazione appena posata.
---
--- Solo se e' nostra da modificare: in rete un'annotazione appena creata lo e'
--- sempre, ma la domanda costa niente e vale anche per i casi che non abbiamo
--- previsto.
function S.applyTo(symbol, player)
    if not (symbol and player) then return end
    if isClient() and symbol.canClientModify then
        local ok, allowed = pcall(function() return symbol:canClientModify() end)
        if ok and allowed == false then return end
    end
    if not symbol.setSharing then return end
    pcall(function() symbol:setSharing(S.vanilla(player)) end)
end

return NW_Share
