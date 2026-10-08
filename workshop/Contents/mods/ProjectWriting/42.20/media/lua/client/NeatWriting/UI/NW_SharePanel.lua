--[[ ============================================================================
    NW_SharePanel - con chi stai scrivendo, in cinque righe.

    Si apre dal tasto con l'aeroplanino, nell'intestazione del pannello
    Writing, e si chiude scegliendo: e' una scelta, non una finestra da
    amministrare. Per questo NON HA LA CROCE. Una croce serve dove si puo'
    restare a guardare senza decidere; qui ogni riga e' una decisione e la
    decisione chiude da sola. Le due vie d'uscita sono scegliere una riga, o
    ripremere l'aeroplanino che l'ha aperta.

    LE CINQUE RIGHE SONO QUELLE DEL SERVER, e non se ne inventano altre - solo
    io, la mia fazione, il mio rifugio, questi giocatori, tutti - perche' e' il
    server a decidere chi vede cosa e gli si parla nella sua lingua
    (`symbol:setSharing`, e per i tratti a mano libera NW_NetServer).

    LA DIFFERENZA CON QUELLO DI VANILLA sta tutta in quando si sceglie. Il
    pannello del gioco chiede la condivisione **dopo**, un'annotazione alla
    volta: si posa il simbolo, lo si seleziona, si apre la finestra, si sceglie.
    Nessuno lo fa due volte. Qui si sceglie **prima**, una volta sola, e da li'
    in poi ogni segno nuovo nasce gia' spartito - simbolo, biglietto o tratto
    che sia - finche' non si cambia idea. La scelta e' nella modData del
    giocatore (NW_Share) e resta anche dopo che si e' chiuso il gioco.

    L'ARANCIONE E' LO STATO ACCESO, ed e' la regola di famiglia, non una scelta
    fatta per questo pannello: il verde segna quello che e' selezionato adesso,
    l'arancione quello che resta acceso anche dopo che hai guardato altrove. Una
    condivisione attiva e' esattamente questo, e per la stessa ragione resta
    acceso anche l'aeroplanino nell'intestazione: finche' e' arancione quello
    che scrivi non e' solo tuo. Si spegne tornando su "solo io".

    L'ELENCO DEI GIOCATORI E' UN PANNELLO A PARTE (NW_PlayerPanel), e si apre a
    SINISTRA di questo. Stando dentro faceva crescere la finestra sotto le
    altre e le si sovrapponeva; e soprattutto mescolava due domande diverse -
    "con che categoria scrivo" e "quali persone" - in una lista sola dove la
    seconda sembrava un sotto-caso della prima invece che il suo seguito.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Share"
require "NeatWriting/NW_Style"

NW_SharePanel = ISPanel:derive("NW_SharePanel")
NW_PlayerPanel = ISPanel:derive("NW_PlayerPanel")

local PAD = 10
local GAP = 4
local WIDTH = 250
local MAX_PLAYERS_SHOWN = 8

NW_SharePanel.instance = nil
NW_PlayerPanel.instance = nil

--- Le cinque scelte, nell'ordine in cui si leggono: dalla piu' chiusa alla piu'
--- aperta, cosi' "solo io" e "tutti" stanno agli estremi e non si scambiano per
--- sbaglio.
local ROWS = {
    { mode = "private",   key = "IGUI_NW_ShareOnlyMe" },
    { mode = "faction",   key = "IGUI_NW_ShareFaction" },
    { mode = "safehouse", key = "IGUI_NW_ShareSafehouse" },
    { mode = "players",   key = "IGUI_NW_SharePlayers" },
    { mode = "all",       key = "IGUI_NW_ShareEveryone" },
}

local function player()
    return getSpecificPlayer(0)
end

--- In prova si stampa il clic PRIMA di fare qualunque cosa.
---
--- NW_Share.set ha gia' la sua riga, ma le due dicono cose diverse: questa dice
--- che il clic e' arrivato al tasto, quella che la scelta e' stata scritta.
--- Senza la prima, un clic che non arriva e una scelta che non si scrive sono
--- lo stesso silenzio, e sono due guasti in due posti opposti.
local function probe(text)
    if NW_NetClient and NW_NetClient.verbose then print("NW_SharePanel: " .. text) end
end

-- ---------------------------------------------------------------------------
-- Lo scoreboard
-- ---------------------------------------------------------------------------

--- L'ultimo elenco di giocatori che il server ci ha mandato.
local scoreboard = nil

Events.OnScoreboardUpdate.Add(function(usernames, displayNames)
    scoreboard = { usernames = usernames, displayNames = displayNames }
    if NW_PlayerPanel.instance then NW_PlayerPanel.instance:rebuild() end
end)

--- I nomi da mostrare: quelli online adesso, piu' quelli gia' scelti che in
--- questo momento non ci sono. Un giocatore che si e' disconnesso non deve
--- sparire dalla lista di chi puo' leggere: sparirebbe il suo permesso con lui.
local function knownNames()
    local out, seen = {}, {}
    -- Se stessi no. Il server i propri segni li rimanda sempre - e' la prima
    -- riga di `visibleTo` - quindi scegliersi non cambia niente e toglie un
    -- posto a un nome vero, in una lista che ne mostra otto.
    local me
    pcall(function() me = player():getUsername() end)
    if me and me ~= "" then seen[me] = true end

    if scoreboard and scoreboard.usernames then
        for i = 1, scoreboard.usernames:size() do
            local name = scoreboard.usernames:get(i - 1)
            if name and name ~= "" and not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
    end
    for _, name in ipairs(NW_Share.get(player()).players) do
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    return out
end

local function isChosen(name)
    for _, n in ipairs(NW_Share.get(player()).players) do
        if n == name then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Misure comuni ai due pannelli
-- ---------------------------------------------------------------------------

--- Un pannello che si apre da un'intestazione alta `headerH * scala` deve avere
--- righe e caratteri della stessa taglia, altrimenti a schermo grande resta un
--- francobollo in mezzo al vuoto - che e' il difetto per cui la maniglia e'
--- stata chiesta, visto da qui.
local function metrics(scale)
    local s = scale or 1
    local m = {}
    m.width   = math.floor(WIDTH * s)
    m.headerH = math.floor(22 * s)
    m.rowH    = math.floor(26 * s)
    m.pad     = math.max(6, math.floor(PAD * s))
    m.gap     = math.max(2, math.floor(GAP * s))
    m.font, m.fontH = NW_Style.pickFont(m.rowH - math.floor(8 * s))
    m.titleFont, m.titleH = NW_Style.pickFont(m.headerH - math.floor(6 * s))
    return m
end

--- L'intestazione: icona a sinistra, titolo accanto. Nessun tasto.
--- Il disegno sta in NW_Style, che e' l'unico posto dove le misure
--- dell'intestazione sono definite: qui si sceglie solo cosa scriverci.
local function drawHeader(el, m, iconName, title)
    NW_Style.drawHeaderLabel(el, m.headerH,
        iconName and NW_Style.tex(NW.ICONS .. iconName) or nil,
        title, m.titleFont, m.titleH)
end

-- ---------------------------------------------------------------------------
-- NW_SharePanel - le cinque categorie
-- ---------------------------------------------------------------------------

function NW_SharePanel:createChildren()
    local m = self.m
    self.rowButtons = {}
    for _, row in ipairs(ROWS) do
        local b = ISButton:new(m.pad, 0, self.width - m.pad * 2, m.rowH, "", self,
            NW_SharePanel.onRow)
        b:initialise()
        b:instantiate()
        b:setDisplayBackground(false)
        b.internal = row.mode
        b.render = function() end       -- lo disegna il pannello
        self:addChild(b)
        self.rowButtons[#self.rowButtons + 1] = b
    end
    self:layout()
end

function NW_SharePanel:layout()
    local m = self.m
    local y = m.headerH + m.pad
    for _, b in ipairs(self.rowButtons) do
        b:setY(y)
        y = y + m.rowH + m.gap
    end
    self:setHeight(y - m.gap + m.pad)
end

function NW_SharePanel:onRow(button)
    probe("riga premuta = " .. tostring(button and button.internal))
    local p = player()
    if not p then return end
    local mode = button.internal
    NW_Share.set(p, mode, NW_Share.get(p).players)

    -- "Questi giocatori" non e' una risposta completa: e' una domanda che ne
    -- apre un'altra. L'elenco si apre di fianco, e questo pannello si toglie di
    -- mezzo comunque - la categoria e' scelta.
    local x, y, scale = self:getX(), self:getY(), self.nwScale
    local wantsList = mode == "players"
    self:close("scelta: " .. tostring(mode), wantsList)
    if wantsList then
        -- Chiedere l'elenco costa un giro di rete: si chiede solo qui, e la
        -- risposta arriva quando arriva - il pannello nasce vuoto e si riempie
        -- da se' invece di far aspettare chi ha appena scelto.
        if scoreboardUpdate then pcall(scoreboardUpdate) end
        NW_PlayerPanel.open(x, y, scale)
    end
end

function NW_SharePanel:prerender()
    NW_Style.drawWindow(self, 0, 0, self.width, self.height, self.m.headerH)
end

function NW_SharePanel:render()
    local m = self.m
    drawHeader(self, m, "Share.png", getText("IGUI_NW_Share"))

    local mode = NW_Share.get(player()).mode
    for i, row in ipairs(self.rowButtons) do
        local on = row.internal == mode
        NW_Style.drawWideButton(self, row:getX(), row:getY(), row:getWidth(), row:getHeight(),
            NW_Style.buttonState(on, row:isMouseOver(), row.pressed))
        local c = on and NW_Style.text or NW_Style.dim
        self:drawText(getText(ROWS[i].key), row:getX() + m.pad,
            row:getY() + math.floor((m.rowH - m.fontH) / 2),
            c.r, c.g, c.b, 1, m.font)
    end
end

-- ---------------------------------------------------------------------------
-- NW_PlayerPanel - quali persone
-- ---------------------------------------------------------------------------

function NW_PlayerPanel:createChildren()
    self.buttons = {}
    self:rebuild()
end

function NW_PlayerPanel:rebuild()
    for _, b in ipairs(self.buttons or {}) do self:removeChild(b) end
    self.buttons = {}

    local m = self.m
    self.names = knownNames()
    for i = 1, math.min(#self.names, MAX_PLAYERS_SHOWN) do
        local b = ISButton:new(m.pad, 0, self.width - m.pad * 2, m.rowH, "", self,
            NW_PlayerPanel.onPlayer)
        b:initialise()
        b:instantiate()
        b:setDisplayBackground(false)
        b.internal = self.names[i]
        b.render = function() end
        self:addChild(b)
        self.buttons[i] = b
    end
    self:layout()
end

function NW_PlayerPanel:layout()
    local m = self.m
    local y = m.headerH + m.pad
    for _, b in ipairs(self.buttons) do
        b:setY(y)
        y = y + m.rowH + m.gap
    end
    if #self.buttons == 0 then
        self.emptyY = y
        y = y + m.rowH
    else
        self.emptyY = nil
    end
    self:setHeight(y - m.gap + m.pad)
end

--- Scelto un nome, si chiude. Un giocatore alla volta e' quello che serve:
--- l'elenco si riapre dall'aeroplanino, e una lista che resta aperta mentre si
--- spuntano nomi e' una finestra da amministrare - proprio quello che questo
--- pannello non vuole essere.
function NW_PlayerPanel:onPlayer(button)
    probe("giocatore premuto = " .. tostring(button and button.internal))
    local p = player()
    if not p then return end
    local chosen = NW_Share.get(p)
    local out, found = {}, false
    for _, name in ipairs(chosen.players) do
        if name == button.internal then found = true else out[#out + 1] = name end
    end
    if not found then out[#out + 1] = button.internal end
    NW_Share.set(p, "players", out)
    self:close("scelto " .. tostring(button.internal))
end

function NW_PlayerPanel:prerender()
    NW_Style.drawWindow(self, 0, 0, self.width, self.height, self.m.headerH)
end

function NW_PlayerPanel:render()
    local m = self.m
    drawHeader(self, m, "Character.png", getText("IGUI_NW_SharePlayers"))

    local tick = NW_Style.tex(NW.ICONS .. "Icon_True.png")
    for _, b in ipairs(self.buttons) do
        local on = isChosen(b.internal)
        NW_Style.drawWideButton(self, b:getX(), b:getY(), b:getWidth(), b:getHeight(),
            NW_Style.buttonState(on, b:isMouseOver(), b.pressed))
        local textX = b:getX() + m.pad
        if on and tick then
            local s = math.min(m.fontH, b:getHeight() - 4)
            self:drawTextureScaled(tick, b:getX() + m.pad,
                b:getY() + math.floor((b:getHeight() - s) / 2), s, s, 1,
                NW_Style.text.r, NW_Style.text.g, NW_Style.text.b)
            textX = b:getX() + m.pad + s + math.floor(m.pad / 2)
        end
        local c = on and NW_Style.text or NW_Style.dim
        self:drawText(b.internal, textX,
            b:getY() + math.floor((m.rowH - m.fontH) / 2), c.r, c.g, c.b, 1, m.font)
    end

    if self.emptyY then
        self:drawText(getText("IGUI_NW_ShareNobody"), m.pad * 2, self.emptyY,
            NW_Style.dim.r, NW_Style.dim.g, NW_Style.dim.b, 1, m.font)
    end
end

-- ---------------------------------------------------------------------------
-- Aprire e chiudere - la stessa ricetta per tutti e due
-- ---------------------------------------------------------------------------

--- `why` arriva come stringa quando siamo noi a chiamare.
local function closePanel(self, cls, why)
    -- CHI si chiude, non solo perche'. I due pannelli stampavano con la stessa
    -- etichetta, e "chiuso: clic fuori" poteva essere l'uno o l'altro: per
    -- capirlo bisognava ricostruire la sequenza dalle righe intorno, e un log
    -- che si ricostruisce non e' un log.
    probe((cls == NW_PlayerPanel and "elenco giocatori" or "condivisione")
        .. " chiuso: " .. (type(why) == "string" and why or "?"))
    self:setVisible(false)
    self:removeFromUIManager()
    if cls.instance == self then cls.instance = nil end
end

--- `keepPlayers` lo passa solo la riga "questi giocatori", che si chiude per
--- lasciare il posto all'elenco. Un `why` da confrontare a stringa lo farebbe
--- lo stesso, ma legherebbe il comportamento al testo di un messaggio di prova.
function NW_SharePanel:close(why, keepPlayers)
    -- L'elenco dei giocatori e' figlio di questa scelta: se se ne va lei, se ne
    -- va anche lui. Restare aperto da solo lo renderebbe una finestra orfana,
    -- che modifica una categoria non piu' visibile da nessuna parte.
    if NW_PlayerPanel.instance and not keepPlayers then
        NW_PlayerPanel.instance:close("chiusa la scelta che l'aveva aperto")
    end
    closePanel(self, NW_SharePanel, why)
end

function NW_PlayerPanel:close(why)
    closePanel(self, NW_PlayerPanel, why)
end

--- LA GUARDIA E' QUELLA DI VANILLA, copiata e non inventata. Otto pannelli del
--- gioco aprono questo gestore con la stessa riga - DebugOptionsWindow,
--- SpriteModelEditor, TileGeometryEditor, ISWidgetInput e gli altri - e uno di
--- loro la commenta con "clicked in a child", che e' precisamente il caso
--- nostro: il motore chiama "clic fuori" sul genitore anche quando il clic e'
--- finito su un suo figlio. Chiudersi vuol dire togliersi dal gestore, e
--- ISButton consegna `onclick` sul RILASCIO: sparendo alla pressione, al
--- rilascio non c'e' piu' nessun tasto a cui consegnare il clic.
---
--- Le coordinate qui sono RELATIVE all'elemento, non di schermo (FireBrushUI:
--- `x >= 0 and x <= self:getWidth()`). Confrontarle con il rettangolo assoluto
--- non scatta mai. (lezione 55)
local function outsideDown(self, cls)
    if self:isMouseOver() then return true end
    self:close("clic fuori")
    -- IL TASTO CHE APRE STA FUORI DAL PANNELLO, e senza questa marcatura non
    -- riuscirebbe mai a chiuderlo: alla pressione arriviamo qui e ci chiudiamo
    -- azzerando l'istanza, al rilascio parte l'`onclick` del tasto che trova il
    -- campo vuoto e riapre. Nel log si leggeva "chiuso" e "aperto" a
    -- centodiciassette millisecondi, dallo stesso clic.
    cls.closedAt = getTimestampMs and getTimestampMs() or 0
    return true
end

function NW_SharePanel:onMouseDownOutside(x, y) return outsideDown(self, NW_SharePanel) end
function NW_PlayerPanel:onMouseDownOutside(x, y) return outsideDown(self, NW_PlayerPanel) end

function NW_SharePanel:onMouseDown(x, y) return true end
function NW_SharePanel:onMouseUp(x, y) return true end
function NW_PlayerPanel:onMouseDown(x, y) return true end
function NW_PlayerPanel:onMouseUp(x, y) return true end

--- Mette un pannello sullo schermo e lo tiene dentro i bordi.
local function place(p)
    p:initialise()
    p:instantiate()
    p:addToUIManager()
    -- Sopra la mappa e sopra la finestra di scrittura, che sono tutte e due
    -- setAlwaysOnTop: senza, nascerebbe dietro e non lo troverebbe nessuno.
    p:setAlwaysOnTop(true)
    if p:getX() + p:getWidth() > getCore():getScreenWidth() then
        p:setX(getCore():getScreenWidth() - p:getWidth() - 4)
    end
    if p:getX() < 4 then p:setX(4) end
    if p:getY() + p:getHeight() > getCore():getScreenHeight() then
        p:setY(math.max(4, getCore():getScreenHeight() - p:getHeight() - 4))
    end
    return p
end

--- Vero se il pannello si e' appena chiuso da se': allora il clic sul tasto era
--- "chiudi", e riaprire sarebbe il contrario di quello che si e' chiesto.
local function justClosed(cls)
    local now = getTimestampMs and getTimestampMs() or 0
    if cls.closedAt and now - cls.closedAt < 300 then
        cls.closedAt = nil
        return true
    end
    return false
end

--- Apre il pannello sotto il tasto che l'ha chiamato. Coordinate di schermo.
function NW_SharePanel.open(x, y, scale)
    if NW_SharePanel.instance then
        NW_SharePanel.instance:close("richiamato mentre era gia aperto")
        return nil
    end
    if justClosed(NW_SharePanel) then return nil end

    local p = NW_SharePanel:new(x, y, scale)
    place(p)
    NW_SharePanel.instance = p

    if NW_NetClient and NW_NetClient.verbose then
        local dove = {}
        for i, b in ipairs(p.rowButtons) do
            dove[i] = tostring(b.internal) .. "@" .. tostring(b:getY())
        end
        probe("aperto a " .. p:getX() .. "," .. p:getY()
            .. " misura " .. p:getWidth() .. "x" .. p:getHeight()
            .. " righe: " .. table.concat(dove, " "))
    end
    return p
end

--- L'elenco dei giocatori, A SINISTRA del pannello che l'ha aperto.
---
--- A sinistra e non sotto: il pannello Writing sta nell'angolo destro dello
--- schermo, e qualunque cosa nasca alla sua destra o sotto di lui finisce
--- addosso a lui o fuori dallo schermo. Se pero' a sinistra non c'e' posto, si
--- torna a destra invece di uscire dal bordo - meglio sovrapporsi che sparire.
function NW_PlayerPanel.open(shareX, shareY, scale)
    if NW_PlayerPanel.instance then
        NW_PlayerPanel.instance:close("richiamato mentre era gia aperto")
        return nil
    end
    if justClosed(NW_PlayerPanel) then return nil end

    local p = NW_PlayerPanel:new(0, shareY, scale)
    local x = shareX - p.width - 6
    if x < 4 then x = shareX + math.floor(WIDTH * (scale or 1)) + 6 end
    p:setX(x)
    place(p)
    NW_PlayerPanel.instance = p
    probe("elenco giocatori aperto a " .. p:getX() .. "," .. p:getY()
        .. " con " .. #p.names .. " nomi")
    return p
end

--- Chiude tutt'e due, da fuori. La chiama chi chiude la mappa o il pannello
--- Writing: un selettore che sopravvive a quello che stava configurando resta
--- a mezz'aria sopra il gioco.
function NW_SharePanel.closeAll()
    if NW_PlayerPanel.instance then NW_PlayerPanel.instance:close("chiuso da fuori") end
    if NW_SharePanel.instance then NW_SharePanel.instance:close("chiuso da fuori") end
end

-- ---------------------------------------------------------------------------
-- Costruttori
-- ---------------------------------------------------------------------------

--- `ISPanel.new(cls, ...)` mette gia' lui la metatabella su `cls`: qui non se
--- ne rimette una seconda, che sarebbe la stessa cosa scritta due volte.
local function build(cls, x, y, scale)
    local m = metrics(scale)
    local o = ISPanel.new(cls, x, y, m.width, m.headerH + m.pad * 2 + m.rowH)
    o.background = false
    o.moveWithMouse = false
    o.nwScale = scale or 1
    o.m = m
    o.names = {}
    return o
end

function NW_SharePanel:new(x, y, scale) return build(self, x, y, scale) end
function NW_PlayerPanel:new(x, y, scale) return build(self, x, y, scale) end

return NW_SharePanel
