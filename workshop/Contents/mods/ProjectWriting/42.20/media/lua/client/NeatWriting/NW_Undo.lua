--[[ ============================================================================
    NW_Undo - un passo indietro, con Ctrl+Z.

    Disegnare a mano libera e' l'unico gesto della mod che non si puo' rifare
    identico: un tratto storto si cancella con la gomma e si ridisegna, ma non
    tornera' quello di prima. Da qui la pila.

    COSA SI RIMANGIA. Quello che aggiungiamo noi - tratti, simboli e biglietti
    sulla pagina, tratti sulla mappa - piu' quello che la gomma porta via delle
    stesse cose. I simboli e i biglietti sulla mappa sono di vanilla: li mette e
    li toglie il suo archivio, che di suo un passo indietro non ce l'ha, e
    rimetterli a mano vorrebbe dire ricostruirli campo per campo. Restano fuori,
    ed e' scritto anche nella descrizione.

    UN GESTO, UN PASSO. Una passata di gomma tenuta premuta cancella a ogni
    frame in cui il puntatore incontra qualcosa: se ogni frame fosse un passo,
    Ctrl+Z rimetterebbe un pezzetto per volta e servirebbero venti pressioni per
    disfare una strisciata. Le rimozioni dello stesso gesto - che si riconosce
    dalla sua etichetta, la tabella che lo rappresenta - finiscono percio' tutte
    nella stessa voce.

    NON INDICI MA TABELLE. Le liste si accorciano e gli indici scivolano: una
    voce si ritrova per identita', e l'indice serve solo a rimetterla vicino a
    dov'era.

    DOVE. La pila sta sull'oggetto che possiede il disegno: la pagina o la
    mappa. Chiudere l'una o l'altra se la porta via, ed e' giusto cosi': un
    passo indietro vale finche' si sta guardando quello che si e' fatto.
============================================================================ ]]--

if isServer() then return end

NW_Undo = NW_Undo or {}
local U = NW_Undo

--- Quanti gesti si tengono. Venti sono piu' di quanti se ne chiedano davvero.
local MAX = 20

function U.clear(owner)
    if owner then owner.nwUndo = nil end
end

function U.can(owner)
    return (owner and owner.nwUndo and #owner.nwUndo > 0) and true or false
end

local function stack(owner)
    if not owner.nwUndo then owner.nwUndo = {} end
    return owner.nwUndo
end

local function push(owner, e)
    local st = stack(owner)
    st[#st + 1] = e
    while #st > MAX do table.remove(st, 1) end
end

-- ---------------------------------------------------------------------------
-- Registrare
-- ---------------------------------------------------------------------------

--- La voce e' stata aggiunta: disfare vuol dire toglierla.
function U.pushAdd(owner, list, entry, after)
    if not owner or not list or not entry then return end
    push(owner, { kind = "add", list = list, entry = entry, after = after })
end

--- Le voci sono state tolte: disfare vuol dire rimetterle dov'erano.
---
--- `removed` e' una lista di { list, entry, at }: una passata di gomma puo'
--- portare via cose da liste diverse in un colpo solo. `tag`, quando c'e',
--- tiene insieme le passate dello stesso gesto.
function U.pushRemove(owner, removed, after, tag)
    if not owner or not removed or #removed == 0 then return end

    local st = stack(owner)
    local top = st[#st]
    if tag and top and top.kind == "remove" and top.tag == tag then
        for _, r in ipairs(removed) do top.removed[#top.removed + 1] = r end
        top.after = after or top.after
        return
    end

    push(owner, { kind = "remove", removed = removed, after = after, tag = tag })
end

-- ---------------------------------------------------------------------------
-- Disfare
-- ---------------------------------------------------------------------------

local function detach(list, entry)
    if not list or not entry then return end
    for i = #list, 1, -1 do
        if list[i] == entry then table.remove(list, i) return end
    end
end

local function attach(list, entry, at)
    if not list or not entry then return end
    at = at or (#list + 1)
    if at > #list + 1 then at = #list + 1 end
    if at < 1 then at = 1 end
    table.insert(list, at, entry)
end

--- Disfa l'ultimo gesto. Torna vero se c'era qualcosa da disfare.
function U.undo(owner)
    if not U.can(owner) then return false end
    local e = table.remove(owner.nwUndo)

    local ok, err = pcall(function()
        if e.kind == "add" then
            detach(e.list, e.entry)
        else
            -- All'indietro: gli indici sono stati presi mentre si toglieva in
            -- ordine inverso, e rimettendoli nello stesso verso tornerebbero
            -- spostati di uno.
            for i = #e.removed, 1, -1 do
                local r = e.removed[i]
                attach(r.list, r.entry, r.at)
            end
        end
        if e.after then e.after() end
    end)
    if not ok then print("NW_Undo: " .. tostring(err)) end
    return true
end
