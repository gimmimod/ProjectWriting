--[[ ============================================================================
    NW_Window - la finestra di scrittura: la pagina, e il pannello di fianco.

    Prende tutto lo schermo perche' e' lei a scurirlo: sotto c'e' il mondo in
    pausa, e la pagina sta al centro con il pannello Writing appoggiato al suo
    fianco. Non e' una finestra che si sposta o si ridimensiona - e' una
    modalita', e si esce con la X o con Esc.

    IL GRUPPO. Il pannello non sta inchiodato al bordo destro dello schermo: si
    misura prima quanto puo' essere grande il foglio, poi foglio e pannello
    vengono centrati INSIEME. Cosi' un diario largo e un blocco stretto hanno lo
    stesso pannello sempre appoggiato al bordo della carta.

    IL BUIO E' NOSTRO. La pausa ferma il mondo ma non lo scurisce, e una finestra
    trasparente lascia vedere tutta l'interfaccia del gioco attorno al foglio.
    Lo strato scuro con la vignettatura si disegna in prerender: i figli
    dipingono dopo, quindi pagina e pannello ci restano sopra puliti.

    SFOGLIARE. Le frecce della tastiera cambiano apertura, ma solo quando non si
    sta scrivendo: mentre il cursore lampeggia in un riquadro di testo le frecce
    sono sue, e rubargliele significherebbe non poter tornare indietro di una
    lettera. Sotto la pagina restano comunque due frecce da cliccare, che e'
    anche il modo di scoprire che si puo' sfogliare.

    SALVARE. Non c'e' niente da salvare alla chiusura, perche' non c'e' niente
    che non sia gia' salvato: il testo va nelle pagine dell'oggetto a ogni
    battuta, inchiostro e simboli nel suo modData appena posati. Alla chiusura
    si avvisa solo il server, una volta.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Doc"
require "NeatWriting/NW_Focus"
require "NeatWriting/NW_Layouts"
require "NeatWriting/NW_Sound"
require "NeatWriting/NW_Undo"
require "NeatWriting/NW_Style"
require "NeatWriting/UI/NW_Page"
require "NeatWriting/UI/NW_Writer"
require "NeatWriting/UI/NW_PageInk"
require "NeatWriting/UI/NW_NoteEntry"
require "NeatWriting/UI/NW_Panel"
require "NeatWriting/UI/NW_Tooltip"

NW_Window = ISPanel:derive("NW_Window")

local FONT_SMALL = getTextManager():getFontHeight(UIFont.Small)

-- Il pannello largo, come sulla mappa: qui lo schermo e' tutto nostro e la
-- tavola dei simboli si legge molto meglio con qualche colonna in piu'.
local PANEL_W = NW.PANEL_W_WIDE
local GAP     = 16        -- fra il bordo della carta e il pannello
local MARGIN  = 32        -- aria attorno al gruppo
local NAV_H   = 26        -- la striscia con le frecce, sotto la pagina
local NAV_GAP = 10
-- La stanza che la carta ha su uno schermo 1920x1080 con il pannello alla
-- misura di partenza: il tetto della pagina (pageBox).
local REF_ROOM_W = 1540
local REF_ROOM_H = 1016

-- Lo scurimento. Il valore al centro e' quello che lascia ancora riconoscere la
-- stanza dietro; le fasce lo portano quasi al nero sul bordo dello schermo.
-- Il velo dietro la pagina. E' LEGGERO DI PROPOSITO: a scurire ci pensa la
-- modalita' lettura del gioco, accesa da NW_Focus.read, e un velo pieno sopra
-- la copriva del tutto - restava un rettangolo nero, che e' esattamente quello
-- che si vedeva. Qui resta il minimo che stacca la carta dal mondo, e la
-- vignettatura che porta l'occhio al centro.
local SCRIM   = 0.18
local RINGS   = 10
local RING_A  = 0.028

--- L'unica finestra aperta. Scrivere su due fogli insieme non ha senso.
NW_Window.instance = nil

-- ---------------------------------------------------------------------------
-- Costruzione
-- ---------------------------------------------------------------------------

function NW_Window:instantiate()
    ISPanel.instantiate(self)
    pcall(function() self.javaObject:setWantKeyEvents(true) end)
end

--- Le frecce passano da un evento globale, non da onKeyRelease.
---
--- setWantKeyEvents da solo non e' bastato: la finestra non ha il fuoco della
--- tastiera - ce l'ha il riquadro di scrittura, che sta fuori campo - e i tasti
--- non le arrivavano. Events.OnKeyPressed li vede tutti, e l'unica cura da
--- avere e' staccarsi alla chiusura, altrimenti la finestra chiusa continua a
--- rispondere alle frecce per sempre.
--- Ctrl premuto, destro o sinistro.
local function ctrlDown()
    return Keyboard.isKeyDown(Keyboard.KEY_LCONTROL)
        or Keyboard.isKeyDown(Keyboard.KEY_RCONTROL)
end

function NW_Window:onGlobalKey(key)
    if self.nwClosed then return end

    -- Esc passa da qui e non da onKeyRelease: con la penna in mano il fuoco
    -- della tastiera ce l'ha il riquadro di scrittura, e la finestra i tasti
    -- non li vedrebbe piu'. Un biglietto aperto se lo prende lui: annullare
    -- quello che si sta scrivendo non e' chiudere tutto.
    if key == Keyboard.KEY_ESCAPE then
        if not NW_NoteEntry.instance then self:close() end
        return
    end

    -- Ctrl+Z toglie l'ultimo tratto, simbolo o biglietto. Vale anche mentre si
    -- scrive: il riquadro di vanilla un passo indietro non ce l'ha, quindi non
    -- gli si sta togliendo niente.
    if key == Keyboard.KEY_Z and ctrlDown() then
        if self.page and NW_Undo.undo(self.page) then
            NW_Sound.erase(self.player)
        end
        return
    end

    -- LE FRECCE SFOGLIANO SEMPRE, come Pagina su e Pagina giu'.
    --
    -- Per un po' erano del cursore finche' si scriveva, per non rubare a chi
    -- batte il modo di muoversi dentro una frase. Ma da quando la penna e' in
    -- mano gia' all'apertura, "finche' si scrive" vuol dire sempre: le frecce
    -- non sfogliavano piu' niente, e sfogliare da tastiera - che era una cosa
    -- chiesta - era sparito senza che si vedesse.
    --
    -- Dentro il testo restano il mouse, che porta il cursore su qualunque riga
    -- e in mezzo a qualunque parola, piu' Inizio, Fine e le cancellazioni.
    if self:typingElsewhere() then return end
    if key == Keyboard.KEY_LEFT or key == Keyboard.KEY_PRIOR then self:onPrev()
    elseif key == Keyboard.KEY_RIGHT or key == Keyboard.KEY_NEXT then self:onNext()
    end
end

--- Dove sta la carta e quanto e' grande, con il pannello della misura che ha
--- adesso. Separata perche' la risposta cambia: la maniglia del pannello la
--- rifa' cambiare a meta' lettura, e la pagina deve rifarsi da capo con la
--- stessa regola con cui era nata.
function NW_Window:pageBox(panelW)
    local media = self.media
    local navH = self.spreads > 1 and (NAV_H + NAV_GAP) or 0

    -- Prima quanto spazio resta al foglio, tolto il pannello e l'aria.
    local roomW = self.width - panelW - GAP - MARGIN * 2
    local roomH = self.height - MARGIN * 2 - navH

    -- La pagina tiene il suo rapporto: si incastra sull'asse piu' stretto, e
    -- dove la carta ha righe stampate scende all'aggancio se costa poco.
    local scale = math.min(roomW / media.width, roomH / media.height)

    -- MAI PIU' GRANDE CHE SU UN 1080p. La grafia e' alta 40 pixel su qualunque
    -- schermo (NW_Writer), la pagina invece cresceva con lo schermo: su un 4K la
    -- scrittura era minuscola su un diario enorme, e chi scriveva li' metteva in
    -- una facciata righe e battute che sullo schermo di chi legge non entravano
    -- - e il testo in fondo spariva (segnalazioni 42.21). Con il tetto, da 1080p
    -- in su tutti vedono la stessa pagina con la stessa griglia di scrittura.
    -- La stanza di riferimento e' una costante, non lo schermo di nessuno: il
    -- pannello si allarga a mano, e la griglia non deve dipendere da quello.
    local refScale = math.min(REF_ROOM_W / media.width, (REF_ROOM_H - navH) / media.height)
    scale = math.min(scale, refScale)
    local _, pitch = NW_Writer.font()
    scale = NW_Layouts.pageScale(media, scale, pitch)
    local pw = math.floor(media.width * scale)
    local ph = math.floor(media.height * scale)

    -- Poi il gruppo intero al centro dello schermo.
    local px = math.floor((self.width - (pw + GAP + panelW)) / 2)
    local py = math.floor((self.height - navH - ph) / 2)
    return px, py, pw, ph
end

function NW_Window:createChildren()
    local media = self.media
    local pages = NW_Layouts.pageCount(media, NW_Doc.vanillaPages(self.item))
    self.spreads = NW_Layouts.spreads(media, pages)

    local px, py, pw, ph = self:pageBox(NW.panelWidth(PANEL_W))

    self.page = NW_Page:new(px, py, pw, ph, media, self.item, self.player, self.editable)
    self.page.onPress = NW_PageInk.press
    self.page.onDrag = NW_PageInk.drag
    self.page.onRelease = NW_PageInk.release
    self.page.onOverlay = NW_PageInk.overlay
    self.page.onRightPress = NW_PageInk.rightPress
    self.page:initialise()
    self.page:instantiate()
    self:addChild(self.page)

    self.panel = NW_Panel:new(px + pw + GAP, py, self:surface(), PANEL_W)
    -- Il pannello cresce per contenere la tavola dei simboli invece di farla
    -- scorrere, e si ferma solo quando gli si dice quanto spazio c'e'.
    self.panel.maxHeight = self.height - MARGIN * 2
    self.panel:initialise()
    self.panel:instantiate()
    self:addChild(self.panel)

    -- SI APRE DOVE SI ERA ARRIVATI. Un diario di ottanta pagine che riparte ogni
    -- volta dalla prima vuol dire sfogliarne quaranta prima di poter scrivere
    -- una riga. L'apertura giusta e' quella che contiene l'ultima pagina con
    -- qualcosa sopra; un quaderno ancora vuoto parte, com'e' giusto, dalla prima.
    local last = NW_Doc.lastWrittenPage(self.item, pages)
    if last then
        self.page.spread = math.max(1, math.min(self.spreads,
            math.ceil(last / math.max(1, #media.areas))))
        self.page:refresh()
    end

    if self.spreads > 1 then self:buildNav(px, py + ph + NAV_GAP, pw) end

    -- L'altezza del pannello la decide NW_Panel:layout(), quindi si sa solo
    -- adesso: l'affiancamento vero si fa qui.
    self:sidePanel()
end

--- La carta si rifa' alla misura nuova del pannello.
---
--- La chiama il pannello quando si molla la maniglia. Rifare la pagina invece
--- di allargarla e' voluto: dentro ha uno strato di testo per facciata, tarato
--- sui suoi pixel, e ricalcolare quelli a mano vorrebbe dire riscrivere
--- NW_Page:createChildren da fuori. Quello che c'era scritto e' gia' al
--- sicuro - si salva mentre si scrive, e commit() chiude il conto - quindi la
--- pagina nuova nasce identica a quella vecchia, alla misura giusta.
function NW_Window:refit()
    local old = self.page
    if not old then return end

    local keep = {
        spread = old.spread, tool = old.tool, inkId = old.inkId,
        ink = old.ink, brush = old.brush, symbol = old.symbol,
    }
    old:commit()
    self:removeChild(old)

    local px, py, pw, ph = self:pageBox(self.panel and self.panel:getWidth()
        or NW.panelWidth(PANEL_W))

    local page = NW_Page:new(px, py, pw, ph, self.media, self.item, self.player, self.editable)
    page.onPress = NW_PageInk.press
    page.onDrag = NW_PageInk.drag
    page.onRelease = NW_PageInk.release
    page.onOverlay = NW_PageInk.overlay
    page.onRightPress = NW_PageInk.rightPress
    page:initialise()
    page:instantiate()
    self:addChild(page)
    self.page = page

    page.spread = math.max(1, math.min(page.spreads, keep.spread or 1))
    page.tool, page.inkId, page.ink = keep.tool, keep.inkId, keep.ink
    page.brush, page.symbol = keep.brush, keep.symbol
    page:refresh()

    if self.prevBtn then
        self.navX, self.navY, self.navW = px, py + ph + NAV_GAP, pw
        self.prevBtn:setY(self.navY)
        self.nextBtn:setY(self.navY)
        self:placeNav()
    end
    self:sidePanel()
end

function NW_Window:buildNav(x, y, w)
    local size = NAV_H
    self.navY = y
    self.navX = x
    self.navW = w

    self.prevBtn = NW_Style.newSquareButton(0, y, size,
        NW_Style.tex(NW.ICONS .. "Arrow_Left.png"), self, NW_Window.onPrev)
    self.nextBtn = NW_Style.newSquareButton(0, y, size,
        NW_Style.tex(NW.ICONS .. "Arrow_Right.png"), self, NW_Window.onNext)
    NW_Tooltip.attach(self.prevBtn, getText("IGUI_NW_PrevPage"))
    NW_Tooltip.attach(self.nextBtn, getText("IGUI_NW_NextPage"))
    self:addChild(self.prevBtn)
    self:addChild(self.nextBtn)
    self:placeNav()
end

--- Le frecce ai lati dell'indicatore, tutto centrato sulla pagina.
function NW_Window:placeNav()
    if not self.prevBtn then return end
    local label = self:pageLabel()
    local textW = getTextManager():MeasureStringX(UIFont.Small, label)
    local total = NAV_H * 2 + 16 * 2 + textW
    local left = self.navX + math.floor((self.navW - total) / 2)
    self.prevBtn:setX(left)
    self.nextBtn:setX(left + total - NAV_H)
    self.labelX = left + NAV_H + 16
end

function NW_Window:pageLabel()
    return tostring(self.page and self.page.spread or 1) .. " / " .. tostring(self.spreads)
end

-- ---------------------------------------------------------------------------
-- Il contratto con il pannello
-- ---------------------------------------------------------------------------

--- La superficie: quello che il pannello puo' chiedere a chi lo ospita.
---
--- E' la stessa forma che gli passa la mappa (NW_Map.mapSurface), ed e' il
--- motivo per cui non serve un secondo pannello. Qui cambiano due risposte: si
--- scrive a righe su qualunque carta, e il foglio si puo' rinominare.
function NW_Window:surface()
    local win = self
    return {
        word = true,
        readOnly = not win.editable,
        title = NW_Doc.name(win.item),
        canRename = win.editable,
        onResized = function() win:refit() end,
        onRename = function(name) win:onRename(name) end,
        getPlayer = function() return win.player end,
        onClose = function() win:close() end,
        onTool = function(id) win:onTool(id) end,
        onInk = function(id, erasing)
            win.page.inkId = id
            win.page.ink = NW.inkById(id)
            if erasing then win:onTool("erase") else win.page:refresh() end
        end,
        onWidth = function(v) win.page.brush = v end,
        onSymbol = function(sym) win.page.symbol = sym end,
    }
end

function NW_Window:onTool(id)
    self.page:commit()
    self.page.tool = id
    self.page.grab = nil
    self.page:refresh()
end

function NW_Window:onRename(name)
    NW_Doc.rename(self.item, name, self.player)
    if self.panel then self.panel.surface.title = NW_Doc.name(self.item) end
end

-- ---------------------------------------------------------------------------
-- Sfogliare
-- ---------------------------------------------------------------------------

function NW_Window:goTo(spread)
    if not self.page then return end
    local was = self.page.spread
    self.page:setSpread(spread)
    if self.page.spread ~= was then self:placeNav() end
end

function NW_Window:onPrev() self:goTo(self.page.spread - 1) end
function NW_Window:onNext() self:goTo(self.page.spread + 1) end

--- Vero quando la tastiera e' di un campo A PARTE: il biglietto che si sta
--- scrivendo, o il nome che si sta cambiando. Li' le frecce sono sue, e
--- sfogliare sotto le mani di chi scrive un nome sarebbe una sorpresa.
---
--- Il riquadro di scrittura della pagina NON conta, ed e' una scelta: quello
--- si guida col mouse, che porta il cursore su qualunque riga e in mezzo a
--- qualunque parola. Le frecce restano del libro.
function NW_Window:typingElsewhere()
    if NW_NoteEntry.instance then return true end
    if self.panel and self.panel.renaming then return true end
    return false
end

function NW_Window:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then
        -- Se c'e' un biglietto aperto, Esc annulla quello e basta: chiudere
        -- tutta la finestra sarebbe una risposta sproporzionata a "lascia
        -- perdere questa scritta".
        if NW_NoteEntry.instance then return false end
        self:close()
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Disposizione e disegno
-- ---------------------------------------------------------------------------

--- Appoggia il pannello al fianco della pagina, centrato sull'altezza della
--- carta e comunque dentro lo schermo.
function NW_Window:sidePanel()
    local page, panel = self.page, self.panel
    if not page or not panel then return end

    self.panelH = panel.height
    self.panelW = panel.width
    local y = math.floor(page.y + (page.height - panel.height) / 2)
    local lowest = self.height - MARGIN - panel.height
    if y > lowest then y = lowest end
    if y < MARGIN then y = MARGIN end

    -- Mentre si tira la maniglia la carta e' ancora larga com'era, e il
    -- pannello che cresce finirebbe oltre il bordo dello schermo portandosi
    -- via la maniglia: da fuori non si torna piu' indietro. Qui si ferma al
    -- bordo; al rilascio refit() rifa' la carta e il gruppo torna al centro.
    local x = page.x + page.width + GAP
    local right = self.width - MARGIN - panel.width
    if x > right then x = math.max(MARGIN, right) end

    panel:setX(x)
    panel:setY(y)
end

function NW_Window:prerender()
    -- Il mondo riparte da solo: la pausa va riaffermata a ogni frame.
    NW_Focus.hold()

    if self.panel then
        self.panel.maxHeight = self.height - MARGIN * 2
        if self.panel.height ~= self.panelH or self.panel.width ~= self.panelW then
            self:sidePanel()
        end
    end

    self:renderDim()
end

--- Lo strato scuro, piu' fitto verso il bordo. Le fasce non si sovrappongono:
--- ognuna copre solo la sua cornice, dalla piu' esterna alla piu' interna.
function NW_Window:renderDim()
    self:drawRect(0, 0, self.width, self.height, SCRIM, 0, 0, 0)

    local step = math.floor(math.min(self.width, self.height) * 0.04)
    if step < 2 then return end

    for i = 1, RINGS do
        local d = (i - 1) * step
        local w = self.width - d * 2
        local h = self.height - d * 2
        if w <= step * 2 or h <= step * 2 then break end
        local a = RING_A * (RINGS + 1 - i)
        self:drawRect(d, d, w, step, a, 0, 0, 0)
        self:drawRect(d, self.height - d - step, w, step, a, 0, 0, 0)
        self:drawRect(d, d + step, step, h - step * 2, a, 0, 0, 0)
        self:drawRect(self.width - d - step, d + step, step, h - step * 2, a, 0, 0, 0)
    end
end

function NW_Window:render()
    if self.prevBtn then
        self:drawText(self:pageLabel(), self.labelX,
            self.navY + math.floor((NAV_H - FONT_SMALL) / 2),
            NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, UIFont.Small)
    end
end

--- Un clic fuori dalla pagina e dal pannello non deve arrivare al mondo dietro.
function NW_Window:onMouseDown() return true end
function NW_Window:onMouseUp() return true end

-- ---------------------------------------------------------------------------
-- Aprire e chiudere
-- ---------------------------------------------------------------------------

function NW_Window:close()
    if self.nwClosed then return end
    self.nwClosed = true
    if self.keyHandler then
        Events.OnKeyPressed.Remove(self.keyHandler)
        self.keyHandler = nil
    end
    if self.page then self.page:commit() end
    NW_Sound.close(self.player)
    if NW_Window.instance == self then NW_Window.instance = nil end
    NW_Focus.unread(self.player)
    NW_Focus.release()
    self:setVisible(false)
    self:removeFromUIManager()
    -- L'azione a tempo che tiene il personaggio a scrivere finisce con noi,
    -- come fa il diario di vanilla quando si preme OK.
    if self.player then pcall(function() ISTimedActionQueue.clear(self.player) end) end
end

--- ISWriteSomething chiama destroy() sul suo modal: e' lo stesso gesto.
function NW_Window:destroy()
    self:close()
end

--- Apre la finestra su un oggetto. nil se quell'oggetto non e' roba nostra:
--- chi chiama lascia allora fare a vanilla.
function NW_Window.open(item, player, editable)
    local media = NW_Layouts.forItem(item)
    if not media then return nil end

    if NW_Window.instance then NW_Window.instance:close() end

    -- Un quaderno chiuso a chiave si legge e non si scrive, COME IN VANILLA - e
    -- in vanilla il lucchetto ferma gli ALTRI, non chi l'ha chiuso, e non un
    -- amministratore. Qui prima bastava che un lucchetto ci fosse: chi aveva
    -- chiuso il proprio diario non poteva piu' scriverci nemmeno lui.
    local locked = false
    pcall(function()
        local by = item:getLockedBy()
        locked = by ~= nil and by ~= player:getUsername() and not isAdmin()
    end)

    local win = NW_Window:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    win.item = item
    win.player = player
    win.editable = (editable ~= false) and not locked
    win.media = media

    win:initialise()
    win:instantiate()
    win:addToUIManager()
    win:setAlwaysOnTop(true)

    NW_Focus.take()
    NW_Focus.read(player)
    win.keyHandler = function(key) win:onGlobalKey(key) end
    Events.OnKeyPressed.Add(win.keyHandler)

    -- La penna e' gia' in mano. "Scrivi qualcosa" di vanilla apre un campo di
    -- testo e basta: aprire invece una pagina su cui bisogna prima scegliere
    -- uno strumento per poter scrivere fa sembrare rotto quello che e' solo
    -- disarmato - il cursore non c'e', Invio non fa niente, e la pagina sembra
    -- non rispondere. Gli altri strumenti restano a un clic di distanza.
    --
    -- Dopo addToUIManager, non prima: la finestra che entra nel gestore rimette
    -- a posto il fuoco della tastiera, e un cursore acceso prima verrebbe spento
    -- subito dopo.
    if win.editable then
        if win.panel then win.panel:setTool("text") end
        win:onTool("text")
    end

    NW_Sound.open(player)
    NW_Window.instance = win
    return win
end

function NW_Window:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.moveWithMouse = false
    o.nwClosed = false
    return o
end

return NW_Window
