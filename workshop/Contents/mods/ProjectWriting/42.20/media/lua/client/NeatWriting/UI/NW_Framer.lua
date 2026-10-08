--[[ ============================================================================
    NW_Framer - inquadrare un pezzo di mappa.

    Si accende dal tasto "crea mappa annotata", si trascina un rettangolo sulla
    mappa del mondo, si lascia, si da' un nome. Poi c'e' una mappa di carta in
    tasca e un foglio in meno.

    E' UN VELO SOPRA LA MAPPA, non un pannello: copre tutta la finestra della
    mappa e si prende i clic finche' e' acceso. Deve essere cosi', perche' sotto
    di lui la mappa ha gia' un significato per ogni gesto - trascinare sposta la
    vista, il sinistro disegna, il destro chiede l'autore - e un rettangolo da
    inquadrare non puo' contendersi il mouse con tutto quello. Acceso il velo,
    il mouse fa una cosa sola; spento, la mappa torna quella di prima.

    IL RETTANGOLO SI NORMALIZZA. Si puo' trascinare da qualunque angolo verso
    qualunque altro, e i due punti diventano sempre alto-sinistra e
    basso-destra: chi inquadra non deve pensare da che parte ha cominciato.

    LA MISURA MINIMA non e' un capriccio: un rettangolo di pochi pixel produce
    una mappa che non si puo' leggere e costa un foglio lo stesso. Sotto la
    soglia il velo non fabbrica niente e lo dice.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "NeatWriting/NW_Style"
require "NeatWriting/NW_Cartography"
require "NeatWriting/NW_Sound"
require "NeatWriting/UI/NW_NamePanel"

NW_Framer = ISPanel:derive("NW_Framer")

NW_Framer.instance = nil

--- Meno di tanto per lato e non e' un'area, e' un clic andato storto.
local MIN_PIXELS = 24

local function say(text)
    if NW_NetClient and NW_NetClient.verbose then print("NW_Framer: " .. text) end
end

-- ---------------------------------------------------------------------------
-- Il gesto
-- ---------------------------------------------------------------------------

function NW_Framer:onMouseDown(x, y)
    self.dragging = true
    self.x1, self.y1 = x, y
    self.x2, self.y2 = x, y
    return true
end

function NW_Framer:onMouseMove(dx, dy)
    if not self.dragging then return end
    self.x2 = self:getMouseX()
    self.y2 = self:getMouseY()
end

--- Fuori dai bordi il trascinamento non si annulla: si continua a seguire il
--- mouse, perche' chi inquadra arriva spesso oltre il bordo della finestra e
--- perdere il rettangolo li' sarebbe solo un dispetto.
function NW_Framer:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function NW_Framer:onMouseUp(x, y)
    if not self.dragging then return true end
    self.dragging = false
    self.x2, self.y2 = x, y
    self:finish()
    return true
end

function NW_Framer:onMouseUpOutside(x, y)
    return self:onMouseUp(self:getMouseX(), self:getMouseY())
end

--- Il tasto destro annulla: e' il gesto che tutti provano per primo quando si
--- sono pentiti, e non deve chiedere di indovinare dove sta la via d'uscita.
function NW_Framer:onRightMouseDown(x, y)
    self:close("annullato")
    return true
end

function NW_Framer:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then self:close("annullato con Esc") end
end

--- I due angoli, messi in ordine e in coordinate di mondo.
function NW_Framer:rect()
    local sx1, sx2 = math.min(self.x1, self.x2), math.max(self.x1, self.x2)
    local sy1, sy2 = math.min(self.y1, self.y2), math.max(self.y1, self.y2)
    return sx1, sy1, sx2, sy2
end

local function worldAt(mapUI, x, y)
    local api
    pcall(function() api = mapUI.javaObject:getAPIv1() end)
    if not api then return nil end
    local wx, wy
    local ok = pcall(function()
        wx = api:uiToWorldX(x, y)
        wy = api:uiToWorldY(x, y)
    end)
    if not ok then return nil end
    return wx, wy
end

-- ---------------------------------------------------------------------------
-- Quello che succede quando si lascia
-- ---------------------------------------------------------------------------

function NW_Framer:finish()
    local sx1, sy1, sx2, sy2 = self:rect()
    if sx2 - sx1 < MIN_PIXELS or sy2 - sy1 < MIN_PIXELS then
        self:warn(getText("IGUI_NW_MapTooSmall"))
        return
    end

    -- Le coordinate del velo sono le sue; la mappa sta sotto e ha le proprie.
    local mapUI = self.mapUI
    local ox = self:getAbsoluteX() - mapUI:getAbsoluteX()
    local oy = self:getAbsoluteY() - mapUI:getAbsoluteY()
    -- TUTTI E QUATTRO GLI ANGOLI, non due.
    --
    -- La mappa del mondo non e' allineata agli assi del mondo: si vede dalla
    -- firma della funzione che la interroga, `uiToWorldX(x, y)`, che prende
    -- TUTTE E DUE le coordinate dello schermo - se la trasformazione fosse
    -- allineata, la x del mondo dipenderebbe solo dalla x dello schermo.
    --
    -- Quindi un rettangolo disegnato sullo schermo diventa un ROMBO nel mondo, e
    -- prendere gli angoli in alto a sinistra e in basso a destra da' due punti
    -- quasi sulla stessa diagonale: la scatola che ne esce e' schiacciata. Nel
    -- log si leggeva `10554,10376 -> 10849,10400` - duecentonovantacinque
    -- quadrati per ventiquattro - per un riquadro che a schermo era quasi
    -- quadrato, e la mappa fabbricata era una striscia con i disegni fuori.
    --
    -- Convertendo i quattro angoli e prendendo il minimo e il massimo si ottiene
    -- il rettangolo di mondo che CONTIENE quello che hai inquadrato. Sborda un
    -- po' sugli angoli, ed e' inevitabile: un rombo non sta dentro una scatola
    -- allineata senza avanzo. Meglio un po' di mondo in piu' che i propri segni
    -- fuori dal foglio.
    local wx1, wy1, wx2, wy2
    for _, corner in ipairs({ { sx1, sy1 }, { sx2, sy1 }, { sx1, sy2 }, { sx2, sy2 } }) do
        local wx, wy = worldAt(mapUI, corner[1] + ox, corner[2] + oy)
        if wx and wy then
            wx1 = math.min(wx1 or wx, wx); wx2 = math.max(wx2 or wx, wx)
            wy1 = math.min(wy1 or wy, wy); wy2 = math.max(wy2 or wy, wy)
        end
    end
    if not (wx1 and wx2 and wy1 and wy2) then
        self:warn(getText("IGUI_NW_MapFailed"))
        return
    end

    wx1, wx2 = math.floor(wx1), math.ceil(wx2)
    wy1, wy2 = math.floor(wy1), math.ceil(wy2)

    local strokes, symbols = NW_Cartography.survey(mapUI, self.player, wx1, wy1, wx2, wy2)
    say("rettangolo " .. wx1 .. "," .. wy1 .. " -> " .. wx2 .. "," .. wy2
        .. ": " .. strokes .. " tratti, " .. symbols .. " simboli")
    if strokes == 0 and symbols == 0 then
        self:warn(getText("IGUI_NW_MapEmpty"))
        return
    end

    self.pending = { wx1, wy1, wx2, wy2 }
    self:askName()
end

--- Il nome, chiesto in un pannello Neat al centro dello schermo.
---
--- NON PIU' UN CAMPO NUDO SUL VELO. Prima si apriva NW_NoteEntry - lo stesso
--- campo dei biglietti sulla mappa - appoggiato accanto al rettangolo: senza
--- cornice non si distingueva da un'annotazione che si sta scrivendo SULLA
--- mappa, che e' il gesto di fianco, e non c'era niente da premere per dire
--- "si'". Un oggetto che restera' in giro per la partita merita una finestra
--- che dica cosa sta per succedere e una spunta da premere.
function NW_Framer:askName()
    local suggested = getText("IGUI_NW_MapOf", NW_Cartography.nameOf(self.player))
    self.naming = true
    NW_NamePanel.open({
        title = getText("IGUI_NW_MapMake"),
        icon = "CreateMapNote.png",
        initial = suggested,
        scale = self.nwScale,
        onDone = function(name) self:create(name) end,
        onCancel = function() self:close("nome annullato") end,
    })
end

function NW_Framer:create(title)
    local r = self.pending
    if not r then self:close("niente da creare") return end
    local item, why = NW_Cartography.makeAnnotated(self.mapUI, self.player,
        r[1], r[2], r[3], r[4], title)
    if not item then
        self:warn(getText(why == "nopaper" and "IGUI_NW_MapNoPaper"
            or why == "nopen" and "IGUI_NW_MapNoPen"
            or "IGUI_NW_MapFailed"))
        self.naming = false
        return
    end
    say("fatta: " .. tostring(title))
    NW_Sound.note(self.player)
    self:close("fatta")
end

--- Un messaggio che resta un momento sul velo, invece di un popup: si sta
--- inquadrando, e una finestra da chiudere in mezzo a un gesto lo interrompe.
function NW_Framer:warn(text)
    self.message = text
    self.messageUntil = (getTimestampMs and getTimestampMs() or 0) + 2500
    self.dragging = false
    self.pending = nil
    self.naming = false
end

-- ---------------------------------------------------------------------------
-- Disegno
-- ---------------------------------------------------------------------------

function NW_Framer:render()
    local a = NW_Style.accent

    -- Il velo: appena percettibile, quel tanto che dice "adesso il mouse fa
    -- un'altra cosa". Piu' scuro coprirebbe la mappa che si sta inquadrando.
    self:drawRect(0, 0, self.width, self.height, 0.18, 0, 0, 0)

    if self.x1 and (self.dragging or self.pending) then
        local sx1, sy1, sx2, sy2 = self:rect()
        local w, h = sx2 - sx1, sy2 - sy1
        -- Dentro il rettangolo si torna a vedere la mappa com'e': e' quello che
        -- finira' sul foglio, e va guardato senza filtri sopra.
        self:drawRect(sx1, sy1, w, h, 0.12, a.r, a.g, a.b)
        self:drawRectBorder(sx1, sy1, w, h, 1, a.r, a.g, a.b)
        -- Gli angoli marcati: dicono dove si puo' prendere, e rendono leggibile
        -- un rettangolo sottile sopra una mappa piena di righe.
        local c = math.min(12, math.floor(math.min(w, h) / 3))
        if c > 2 then
            self:drawRect(sx1, sy1, c, 2, 1, a.r, a.g, a.b)
            self:drawRect(sx1, sy1, 2, c, 1, a.r, a.g, a.b)
            self:drawRect(sx2 - c, sy2 - 2, c, 2, 1, a.r, a.g, a.b)
            self:drawRect(sx2 - 2, sy2 - c, 2, c, 1, a.r, a.g, a.b)
        end
    end

    local font, fh = NW_Style.pickFont(18)
    local text = getText("IGUI_NW_MapFrameHint")
    if self.message then
        local now = getTimestampMs and getTimestampMs() or 0
        if now > (self.messageUntil or 0) then
            self.message = nil
        else
            text = self.message
        end
    end
    local tw = getTextManager():MeasureStringX(font, text)
    local bx = math.floor((self.width - tw) / 2) - 8
    local by = 12
    NW_Style.drawGroup(self, bx, by, tw + 16, fh + 8, 0.9)
    self:drawText(text, bx + 8, by + 4,
        NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, font)
end

-- ---------------------------------------------------------------------------
-- Accendere e spegnere
-- ---------------------------------------------------------------------------

function NW_Framer:close(why)
    say("chiuso: " .. tostring(why))
    self:setVisible(false)
    self:removeFromUIManager()
    if NW_Framer.instance == self then NW_Framer.instance = nil end
end

--- Copre la finestra della mappa e si prende i clic. `mapUI` e' la mappa vera,
--- quella che sa tradurre schermo in mondo.
function NW_Framer.open(mapUI, player, scale)
    if NW_Framer.instance then
        NW_Framer.instance:close("richiamato mentre era gia aperto")
        return nil
    end
    if not (mapUI and player) then return nil end

    local p = NW_Framer:new(mapUI:getAbsoluteX(), mapUI:getAbsoluteY(),
        mapUI:getWidth(), mapUI:getHeight())
    p.mapUI = mapUI
    p.player = player
    -- La scala del pannello Writing, cosi' il pannello del nome nasce della
    -- stessa taglia di quello da cui e' stato chiesto invece che a misura 1.
    p.nwScale = scale or 1
    p:initialise()
    p:instantiate()
    p:addToUIManager()
    p:setAlwaysOnTop(true)
    p:setCapture(true)
    NW_Framer.instance = p
    say("acceso su " .. mapUI:getWidth() .. "x" .. mapUI:getHeight())
    return p
end

function NW_Framer:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.moveWithMouse = false
    o.dragging = false
    return o
end

return NW_Framer
