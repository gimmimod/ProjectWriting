--[[ ============================================================================
    NW_Placing - misura e angolo di un segno MENTRE lo si posa.

    Prima un simbolo nasceva alla misura dell'ultimo ridimensionato e dritto, e
    un biglietto nasceva sempre dritto: per girarlo o ingrandirlo serviva un
    secondo strumento, dopo (segnalazione 42.21). Adesso si decide prima:

        Ctrl  + rotella   la misura, un dieci per cento per scatto
        Shift + rotella   l'angolo, quindici gradi per scatto

    con il simbolo in mano sulla mappa (l'anteprima sotto il puntatore lo fa
    vedere gia' girato e alla misura giusta), o con il biglietto aperto e il
    puntatore sopra.

    LA ROTELLA SENZA TASTI RESTA DELLA MAPPA. Lo zoom e' la cosa che si fa piu'
    spesso con la rotella, e un'opzione che lo rubasse sarebbe la prima a
    essere spenta. Per chi i due tasti li usa gia' per altro c'e' l'opzione
    "Misura e angolo mentre si posa" (NW.prefs.placeAdjust), accesa di serie.

    L'ANGOLO E' IN GRADI, come lo vuole setRotation: e' la stessa unita' che
    usa lo strumento Ruota di vanilla (ISWorldMapSymbolTool_RotateAnnotation).
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Config"
require "ISUI/Maps/ISMap"
require "ISUI/Maps/ISWorldMap"
require "ISUI/Maps/ISWorldMapSymbols"
require "NeatWriting/Patches/NW_Ink"

NW_Placing = NW_Placing or {}
local P = NW_Placing

-- L'angolo del prossimo simbolo. La misura invece sta gia' in NW.lastSize: e'
-- la stessa che lo strumento Modifica si ricorda, e due ricordi della stessa
-- cosa prima o poi direbbero due numeri diversi.
P.symAngle = P.symAngle or 0

local STEP_SCALE = 1.1
local STEP_ANGLE = 15
local MIN_SCALE, MAX_SCALE = 0.25, 6

function P.enabled()
    return NW.prefs.placeAdjust ~= false
end

--- Che cosa chiede questa rotella: "size", "angle" o nil (cioe' lo zoom).
--- I tasti si leggono da Keyboard, non con isCtrlKeyDown/isShiftKeyDown.
--- Quelli passano da GameKeyboard.isKeyDown, che risponde sempre falso mentre
--- un campo di testo sta scrivendo (Core.currentTextEntryBox, letto nel
--- bytecode): col biglietto aperto Ctrl e Shift per il gioco non c'erano, e la
--- rotella sul biglietto non faceva niente mentre sul simbolo si'.
local function down(a, b)
    return Keyboard.isKeyDown(a) or Keyboard.isKeyDown(b)
end

function P.gesture()
    if not P.enabled() then return nil end
    if down(Keyboard.KEY_LCONTROL, Keyboard.KEY_RCONTROL) then return "size" end
    if down(Keyboard.KEY_LSHIFT, Keyboard.KEY_RSHIFT) then return "angle" end
    return nil
end

--- Rotella in su (del negativo, come per lo zoom di vanilla) = piu' grande.
function P.nextScale(s, del)
    local f = (del < 0) and STEP_SCALE or (1 / STEP_SCALE)
    return math.max(MIN_SCALE, math.min(MAX_SCALE, (s or 1) * f))
end

--- Rotella in su = senso antiorario, come lo strumento Ruota trascinato in su.
function P.nextAngle(a, del)
    local d = (del < 0) and STEP_ANGLE or -STEP_ANGLE
    return ((a or 0) + d) % 360
end

-- ---------------------------------------------------------------------------
-- La rotella
-- ---------------------------------------------------------------------------
--[[ CHI CAMBIA MISURA E ANGOLO E' L'EVENTO, NON L'ELEMENTO SOTTO IL PUNTATORE.

    La prima versione lo faceva nel gestore della rotella della mappa e in quello
    del biglietto: funzionava solo col puntatore esattamente sopra la cosa giusta
    (il biglietto e' una riga sottile, e appena scritto il puntatore e' gia'
    altrove), e da fuori sembrava che la rotella non facesse niente.

    Il motore lancia l'evento Lua OnMouseWheel a ogni scatto, dopo aver passato
    la rotella alle finestre, e lo lancia comunque sia andato quel giro
    (UIManager.update, letto nel bytecode). Quindi: l'evento cambia misura e
    angolo; i gestori della mappa e del biglietto servono solo a non far
    zoomare la mappa mentre si tiene Ctrl o Shift. Cosi' non c'e' doppio passo.
]]

-- La mappa su cui si sta posando un simbolo adesso. La rinfresca l'anteprima a
-- ogni fotogramma: se smette di disegnarsi, lo strumento non e' piu' in mano.
local placing = { map = nil, at = 0 }

local function placingNow()
    if not placing.map then return nil end
    if getTimestampMs() - placing.at > 250 then
        placing.map = nil
        return nil
    end
    return placing.map
end

-- Lo stesso per un foglio (NW_Page): il simbolo li' lo posa la mod stessa
-- (NW_PageInk), e la sua anteprima si fa vedere da qui a ogni fotogramma.
-- L'angolo e' un ricordo a parte, come la misura (NW.lastSize "page"): un
-- simbolo girato sulla mappa non deve far nascere girati quelli del diario.
local placingPage = { page = nil, at = 0 }
P.pageAngle = P.pageAngle or 0

function P.notePageSymbol(page)
    placingPage.page, placingPage.at = page, getTimestampMs()
end

local function pageNow()
    if not placingPage.page then return nil end
    if getTimestampMs() - placingPage.at > 250 then
        placingPage.page = nil
        return nil
    end
    return placingPage.page
end

local function noteOpen()
    local e = rawget(_G, "NW_NoteEntry") and NW_NoteEntry.instance
    if e and e:isVisible() then return e end
    return nil
end

--- Vero se in questo momento la rotella con Ctrl o Shift e' nostra.
function P.wheelIsOurs()
    if not P.gesture() then return false end
    return noteOpen() ~= nil or placingNow() ~= nil or pageNow() ~= nil
end

local function onWheel(del)
    local g = P.gesture()
    if not g then return end
    -- L'evento riceve lo stato grezzo della rotella (Mouse.getWheelState): in su
    -- e' positivo, mentre alle finestre arriva col segno opposto (UIManager.update).
    -- Qui si riporta al verso delle finestre, quello che usano nextScale e nextAngle.
    del = -(tonumber(del) or 0)
    if del == 0 then return end

    local entry = noteOpen()
    if entry then
        if g == "size" then
            entry.scale = P.nextScale(entry.scale or 1, del)
        else
            entry.angle = P.nextAngle(entry.angle or 0, del)
        end
        return
    end

    if placingNow() then
        if g == "size" then
            NW.setLastSize("map", "sym", P.nextScale(NW.lastSize("map", "sym"), del))
        else
            P.symAngle = P.nextAngle(P.symAngle, del)
        end
        return
    end

    if pageNow() then
        if g == "size" then
            NW.setLastSize("page", "sym", P.nextScale(NW.lastSize("page", "sym"), del))
        else
            P.pageAngle = P.nextAngle(P.pageAngle, del)
        end
    end
end
Events.OnMouseWheel.Add(function(del) pcall(onWheel, del) end)

--- Gira un simbolo appena posato. La misura gliel'ha gia' data dressMark.
function P.applyAngle(sym)
    if not sym or not P.enabled() then return end
    if (P.symAngle or 0) ~= 0 then
        pcall(function() sym:setRotation(P.symAngle) end)
    end
end

-- La mappa non zooma mentre la rotella serve a noi.
for _, cls in ipairs({ ISWorldMap, ISMap }) do
    if cls and cls.onMouseWheel then
        local stock = cls.onMouseWheel
        cls.onMouseWheel = function(self, del)
            local ok, ours = pcall(P.wheelIsOurs)
            if ok and ours then return true end
            return stock(self, del)
        end
    end
end

--- La riga che dice a che punto si e', e come cambiarlo. Sempre visibile: al
--- 100 % e dritta e' proprio quando serve sapere che si puo' cambiare.
function P.status(scale, angle)
    local s = tostring(math.floor((scale or 1) * 100 + 0.5)) .. "%  "
        .. tostring(math.floor((angle or 0) + 0.5)) .. string.char(176)
    local hint = getText("IGUI_NW_PlaceHint")
    if hint and hint ~= "IGUI_NW_PlaceHint" then s = s .. "   " .. hint end
    return s
end

-- L'anteprima sotto il puntatore: alla misura e all'angolo con cui il simbolo
-- nascera'. Vanilla la disegna sempre a ISMap.SCALE e dritta, e un simbolo
-- che si posa diverso da come lo si vedeva e' un simbolo posato alla cieca.
local stockRender = ISWorldMapSymbolTool_AddSymbol.render
function ISWorldMapSymbolTool_AddSymbol:render()
    local sui = self.symbolsUI
    local mapUI = sui and sui.mapUI
    -- NON NW_Ink.owns: quello dice se in mano c'e' uno strumento disegnato da noi
    -- (penna, gomma, biglietto, modifica), e il simbolo lo posa lo strumento di
    -- vanilla - owns qui era sempre falso, e anteprima e rotella restavano di
    -- vanilla (collaudo 42.21). Conta che la mappa sia vestita da noi e che il
    -- nostro pannello abbia in mano il simbolo.
    if not (P.enabled() and mapUI and not NW.vanillaMap() and mapUI.nwTool == "symbol"
            and sui.selectedSymbol) then
        return stockRender(self)
    end
    placing.map, placing.at = mapUI, getTimestampMs()

    local x, y = self:getMouseX(), self:getMouseY()
    if (sui.playerNum ~= 0) or (JoypadState.players[sui.playerNum + 1]
            and not wasMouseActiveMoreRecentlyThanJoypad()) then
        x, y = self.mapUI.width / 2, self.mapUI.height / 2
    end
    local scale = ISMap.SCALE * self.mapAPI:getWorldScale() * NW.lastSize("map", "sym")
    sui:renderSymbolAux(sui.selectedSymbol, x, y, P.symAngle or 0, scale, false, false)

    local text = P.status(NW.lastSize("map", "sym"), P.symAngle)
    mapUI:drawText(text, x + 17, y + 15, 0, 0, 0, 0.6, UIFont.Small)
    mapUI:drawText(text, x + 16, y + 14, 1, 1, 1, 0.9, UIFont.Small)
end

return P
