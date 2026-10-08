--[[ ============================================================================
    NW_Follow - la mappa del mondo che segue il personaggio mentre cammina.

    VIENE DA "CENTER MAP" DI TOYSGUNNER, e ne prende la parte migliore. Quella
    mod si prende il tasto "C" di vanilla e gli fa girare tre modi - centra,
    segui, spento - colorandolo di verde e di rosso. Con Project Writing attivo
    le due cose si pestavano i piedi: il nostro tasto e' ridisegnato da noi e i
    suoi colori non si vedevano, quindi il tasto centrava, poi seguiva, poi non
    faceva niente, senza dire quale dei tre. E il suo inseguimento si ferma
    guardando `map.dragging`, che e' il trascinamento di vanilla: il nostro
    spostamento col destro non passa di li', e la vista gli si metteva contro.

    Qui la stessa idea sta su un tasto suo, l'elicottero, e il tasto "C" torna a
    fare una cosa sola (NW_MapButtons).

    SEGUE, NON INCHIODA. La vista si sposta di quanto si e' spostato il
    personaggio dall'ultimo fotogramma, invece di rimettersi ogni volta sopra di
    lui: cosi' si puo' spostare la mappa per guardare piu' in la', e da li' in
    poi la vista si porta dietro quello scostamento. E' la versione 1.2 della mod
    di riferimento, che ci e' arrivata dopo aver provato l'altra.

    NON LOTTA CONTRO LA MANO. Mentre si trascina la mappa - col destro, oppure
    col sinistro a mani vuote - la vista e' di chi trascina, e il personaggio
    che cammina non la tira via.
============================================================================ ]]--

if isServer() then return end

require "ISUI/Maps/ISWorldMap"
require "NeatWriting/NW_Config"

NW_Follow = NW_Follow or {}
local F = NW_Follow

function F.isOn() return NW.mapFollow() end

--- Si segue solo dove c'e' il tasto per smettere. L'elicottero compare con
--- "Center Map" attiva (NW_MapButtons): chi l'ha acceso e poi ha tolto quella
--- mod non deve ritrovarsi una mappa che si muove da sola senza un tasto per
--- fermarla.
local function available(mapUI)
    return mapUI and mapUI.nwFollowBtn ~= nil
end

--- Chi sta guardando questa mappa.
local function playerOf(mapUI)
    return mapUI and (mapUI.character or getSpecificPlayer(mapUI.playerNum or 0))
end

--- Porta subito la vista sul personaggio, con la funzione di vanilla.
function F.center(mapUI)
    if mapUI and mapUI.onCenterOnPlayer then
        pcall(function() mapUI:onCenterOnPlayer() end)
    end
    local p = playerOf(mapUI)
    if p then
        mapUI.nwFollowX, mapUI.nwFollowY = p:getX(), p:getY()
    end
end

--- Accende o spegne. Accendendo si parte centrati: seguire da dove si trova la
--- vista adesso vorrebbe dire seguire un personaggio che magari non si vede.
function F.toggle(mapUI)
    local on = NW.setMapFollow(not F.isOn())
    if on then F.center(mapUI) end
    return on
end

--- Una volta per fotogramma, dalla mappa del mondo aperta.
function F.tick(mapUI)
    if not (available(mapUI) and F.isOn()) then
        if mapUI then mapUI.nwFollowX = nil end
        return
    end
    local p = playerOf(mapUI)
    local api = mapUI.mapAPI
    if not (p and api) then return end

    local x, y = p:getX(), p:getY()
    if not mapUI.nwFollowX then
        mapUI.nwFollowX, mapUI.nwFollowY = x, y
        return
    end

    local dx, dy = x - mapUI.nwFollowX, y - mapUI.nwFollowY
    mapUI.nwFollowX, mapUI.nwFollowY = x, y
    if dx == 0 and dy == 0 then return end

    -- La mano ha la precedenza: il trascinamento di vanilla (sinistro a mani
    -- vuote) e il nostro (destro, NW_Ink).
    local st = mapUI.nwStrokes
    if mapUI.dragging or (st and st.pan) then return end

    pcall(function()
        api:centerOn(api:getCenterWorldX() + dx, api:getCenterWorldY() + dy)
    end)
end

--- Aprendo la mappa: se la vista segue, si parte dal personaggio. Chi l'ha
--- chiusa lontano e la riapre con l'elicottero acceso si aspetta di trovarsi.
function F.onOpen(mapUI)
    if not mapUI then return end
    mapUI.nwFollowX = nil
    if available(mapUI) and F.isOn() then F.center(mapUI) end
end

-- ---------------------------------------------------------------------------
-- Il mondo che non si ferma
-- ---------------------------------------------------------------------------
--
-- Seguire il personaggio su una mappa che mette in pausa il gioco non serve a
-- niente: il personaggio non cammina. Vanilla ha gia' una sua opzione per
-- questo (Opzioni > "Pausa quando si guarda la mappa"), ma sta lontana da dove
-- serve; la nostra, fra le opzioni della mod, dice "non fermare il mondo" e
-- basta. Accesa vince lei; spenta decide l'opzione di vanilla, come prima.
local shouldPause = ISWorldMap and ISWorldMap.shouldPause
if shouldPause then
    ISWorldMap.shouldPause = function(...)
        if NW.prefs.mapNoPause then return false end
        return shouldPause(...)
    end
end

return NW_Follow
