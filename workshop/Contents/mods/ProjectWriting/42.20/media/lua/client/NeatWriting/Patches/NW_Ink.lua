--[[ ============================================================================
    NW_Ink - what our tools do on the map.

    Four of them live here because vanilla either has no equivalent or has one
    that opens a dialog:

      draw    freehand, ours entirely - the map has none
      erase   ours AND vanilla's: a rubber has to take away strokes and symbols
              alike, or "erase" means two different things depending on what is
              under the cursor
      note    the text is typed on the map, not in a modal (NW_NoteEntry)
      edit    resize by dragging, instead of vanilla's edit dialog

    Strokes are polylines in WORLD coordinates, so they stay put while the map
    pans and zooms. They last the session; persistence is Phase 4.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Brush"
require "NeatWriting/NW_MapDoc"
require "NeatWriting/NW_Net"
require "NeatWriting/NW_NetClient"
require "NeatWriting/NW_Share"
require "NeatWriting/NW_Sound"
require "NeatWriting/NW_Undo"
require "NeatWriting/NW_Style"
require "NeatWriting/UI/NW_NoteEntry"
require "NeatWriting/UI/NW_Tooltip"

NW_Ink = NW_Ink or {}
local I = NW_Ink

local ERASE_PIXELS = 9    -- rubber radius, in screen pixels
local MIN_SCALE, MAX_SCALE = 0.2, 8.0

--- Tools that take the mouse away from the map.
local OURS = { draw = true, erase = true, note = true, edit = true }

--- Chi sta guardando questa mappa. ISWorldMap riempie .character solo dopo
--- instantiate(), quindi si chiede ogni volta invece di copiarselo una volta.
local function playerOf(mapUI)
    return mapUI.character or getSpecificPlayer(mapUI.playerNum or 0)
end
I.playerOf = playerOf

--- Lo stato del disegno su questa mappa.
---
--- I tratti NON nascono vuoti: si leggono da dove erano rimasti. Prima stavano
--- solo qui sopra, su un campo dell'oggetto UI, e alla chiusura della mappa se
--- ne andavano con lui - si disegnava, si chiudeva, e non era mai successo
--- niente. Ora la lista e' quella di NW_MapDoc, viva: aggiungere e togliere qui
--- e' disegnare e cancellare, e I.save la manda nella memoria.
function I.state(mapUI)
    if not mapUI.nwStrokes then
        mapUI.nwStrokes = {
            strokes = NW_MapDoc.strokes(mapUI, playerOf(mapUI)),
            active = nil,
        }
    end
    return mapUI.nwStrokes
end

--- Il disegno di questa mappa e' cambiato: mettilo via.
function I.save(mapUI, now)
    NW_MapDoc.touch(mapUI, playerOf(mapUI), now)
end

--- Alla chiusura della mappa: quello che il freno aveva rimandato non ha piu'
--- un dopo in cui essere scritto.
function I.flush(mapUI)
    NW_MapDoc.flush(mapUI, playerOf(mapUI))
end

function I.owns(mapUI)
    return OURS[mapUI.nwTool or ""] == true
end

--- Vero sulla mappa del mondo, falso su una mappa di carta.
---
--- E' la riga che divide le due meta' della mod in rete: quello che si disegna
--- su un oggetto viaggia con l'oggetto e non riguarda nessun altro; quello che
--- si disegna sulla mappa del mondo e' del giocatore, e per farlo vedere a un
--- altro ci vuole il server (NW_NetClient).
local function isWorldMap(mapUI)
    return mapUI ~= nil and mapUI.mapObj == nil
end
I.isWorldMap = isWorldMap

-- ---------------------------------------------------------------------------
-- Quando la mappa e' piena
-- ---------------------------------------------------------------------------
--
-- Il tetto e' in NW_MapDoc, e il perche' pure: sotto c'e' un limite del motore
-- che nessuno ci ha chiesto di rispettare e che, superato, non da' un errore -
-- rompe. Qui c'e' solo quello che il giocatore vede: la penna che si ferma e
-- una riga che dice perche'.
--
-- SI FERMA SOLO LA PENNA. La gomma, i biglietti e i simboli restano: cancellare
-- e' l'unico modo di fare posto, e chiuderlo insieme al resto vorrebbe dire
-- lasciare il giocatore in una stanza senza porta. Biglietti e simboli poi non
-- pesano su questo conto - stanno nell'archivio di vanilla - e bloccarli
-- sarebbe una punizione per una spesa che non hanno fatto.

--- Quanto resta scritto il cartello.
local NOTICE_MS = 4500

--- Alza il cartello adesso.
local function notice(mapUI)
    mapUI.nwNoticeAt = getTimestampMs and getTimestampMs() or 0
end

--- Un tratto appena chiuso: nel deposito di casa ci va comunque, e se c'e'
--- qualcuno con cui spartirlo parte anche di la'.
local function keepAndShare(mapUI, entry)
    local st = I.state(mapUI)
    st.strokes[#st.strokes + 1] = entry
    NW_Undo.pushAdd(mapUI, st.strokes, entry, function() I.save(mapUI, true) end)
    I.save(mapUI, true)
    if isWorldMap(mapUI) then
        NW_NetClient.shareStroke(playerOf(mapUI), entry)
    end
    -- Il tratto che riempie la mappa e' l'ultimo che ci sta: si posa, e il
    -- cartello si alza subito dopo. Cosi' il limite si scopre finendo un segno,
    -- non trovando una penna che non scrive.
    if NW_MapDoc.isFull(mapUI) then notice(mapUI) end
end

-- ---------------------------------------------------------------------------
-- Chi puo' toccare cosa
-- ---------------------------------------------------------------------------

--- Questa annotazione la possiamo modificare?
---
--- In rete un'annotazione non e' automaticamente tua: il server decide chi puo'
--- spostarla, ridimensionarla o cancellarla, e vanilla lo chiede prima di ogni
--- gesto con `filterAny` e `filterEdit`, che sono la stessa riga -
--- `if isClient() and not symbol:canClientModify() then return false end`.
---
--- Noi non lo chiedevamo da nessuna parte: la gomma provava a togliere il
--- simbolo di un altro, il server rifiutava, e da fuori sembrava che la gomma
--- non funzionasse. Peggio, il riquadro arancione compariva lo stesso, quindi
--- la mod prometteva un gesto che non poteva mantenere.
---
--- Da soli si puo' sempre: la domanda vale per un client, e un client non c'e'.
---
--- Il metodo si guarda prima di chiamarlo. In Kahlua chiamare un nil e'
--- un'eccezione Java che il pcall non ferma (lezione 33), e su una build che
--- non avesse questo metodo la gomma smetterebbe di funzionare del tutto.
local function mayModify(sym)
    if not sym then return false end
    if not isClient() then return true end
    if not sym.canClientModify then return true end
    local ok, allowed = pcall(function() return sym:canClientModify() end)
    if not ok then return true end
    return allowed ~= false
end

I.mayModify = mayModify

local function api(mapUI) return mapUI.mapAPI end
local function symbols(mapUI)
    local sui = mapUI.symbolsUI
    return sui and sui.symbolsAPI or nil
end

local function worldAt(mapUI, x, y)
    return api(mapUI):uiToWorldX(x, y), api(mapUI):uiToWorldY(x, y)
end

--- Screen pixels to world units, so a radius feels the same at any zoom.
local function worldRadius(mapUI, pixels)
    local scale = api(mapUI):getWorldScale()
    if not scale or scale <= 0 then return pixels end
    return pixels / scale
end

--- Lo zoom a cui la penna vale il suo numero in pixel, per QUESTA mappa.
---
--- La mappa del mondo si apre sempre a 18 - lo mette ISWorldMap.ShowWorldMap -
--- e li' la penna 3 e' larga 3 pixel, com'e' sempre stata. Una mappa di carta
--- invece si apre adattata al suo ritaglio, e il suo metro e' quello: lo zoom
--- di partenza che il gioco le da', `getBaseZoom`.
local function zoomRef(mapUI)
    if isWorldMap(mapUI) then return NW_Brush.ZOOM_REF end
    local z
    pcall(function() z = api(mapUI):getBaseZoom() end)
    return z or NW_Brush.ZOOM_REF
end

--- Quanti pixel vale adesso un punto di spessore su questa mappa.
local function penScale(mapUI)
    local z
    pcall(function() z = api(mapUI):getZoomF() end)
    return NW_Brush.penScale(z, zoomRef(mapUI))
end

--- Di quanto un punto puo' scostarsi dalla linea, in quadrati di mondo, prima
--- che valga la pena tenerlo.
---
--- Lo spessore del pennello e' in pixel di schermo e i punti del tratto sono
--- in quadrati di mondo: la conversione e' la stessa che serve al raggio della
--- gomma, e senza di essa la semplificazione lavorava mescolando due misure
--- che non hanno niente a che vedere fra loro (NW_Brush.endStroke).
local function worldEpsilon(mapUI, stroke)
    local pixels = (stroke.w or NW.BRUSH.DEFAULT) * penScale(mapUI)
    return worldRadius(mapUI, pixels * NW_Brush.RDP_FACTOR)
end

-- ---------------------------------------------------------------------------
-- Panning, on the right button
-- ---------------------------------------------------------------------------
--
-- IL TASTO SINISTRO NON TRASCINA PIU' LA MAPPA. Faceva due cose a seconda di
-- cosa si aveva in mano - scriveva con uno strumento, muoveva la vista senza -
-- e quando le due si accavallavano il trascinamento restava incastrato: si
-- premeva Sposta un paio di volte e "magicamente" tornava. Non era magia, era
-- un gesto di vanilla rimasto aperto sotto il nostro.
--
-- Adesso ognuno ha il suo: il sinistro e' della penna, il destro della vista.
-- Non c'e' piu' un caso in cui lo stesso pulsante significhi due cose, quindi
-- non c'e' piu' niente da sbloccare.

--- Comincia a spostare la vista. Si tiene lo zoom e il centro di partenza e si
--- ricalcola tutto da quelli, come fa vanilla: aggiornare a ogni frame il punto
--- precedente accumula errore e la mappa scivola da sola.
function I.panDown(mapUI, x, y)
    local a = api(mapUI)
    if not a then return false end
    local st = I.state(mapUI)
    st.pan = {
        x = x, y = y, moved = false,
        cx = a:getCenterWorldX(), cy = a:getCenterWorldY(),
        zoom = a:getZoomF(),
        wx = a:uiToWorldX(x, y), wy = a:uiToWorldY(x, y),
    }
    return true
end

function I.panMove(mapUI)
    local st = mapUI.nwStrokes
    local p = st and st.pan
    if not p then return false end
    local a = api(mapUI)
    if not a then return false end

    local mx, my = mapUI:getMouseX(), mapUI:getMouseY()
    -- Quattro pixel di tolleranza, come vanilla: un clic destro che non si
    -- muove non e' un trascinamento e deve poter significare altro.
    if not p.moved and math.abs(mx - p.x) <= 4 and math.abs(my - p.y) <= 4 then
        return true
    end
    p.moved = true
    local wx = a:uiToWorldX(mx, my, p.zoom, p.cx, p.cy)
    local wy = a:uiToWorldY(mx, my, p.zoom, p.cx, p.cy)
    a:centerOn(p.cx + p.wx - wx, p.cy + p.wy - wy)
    return true
end

-- ---------------------------------------------------------------------------
-- Chi l'ha scritto
-- ---------------------------------------------------------------------------

--- Il nome dell'autore di un'annotazione, se il gioco lo sa e se si puo' dire.
---
--- `isAuthorHidden` e' di vanilla, e va rispettata: un giocatore puo' chiedere
--- che il suo nome non compaia sulle annotazioni, e la nostra etichetta non e'
--- una scorciatoia per aggirarlo.
local function authorOf(mapUI, sym)
    if not sym or not sym.getAuthor then return nil end
    local name
    pcall(function() name = tostring(sym:getAuthor()) end)
    if not name or name == "" or name == "nil" then return nil end

    local hidden = false
    local sapi = symbols(mapUI)
    if sapi and sapi.isAuthorHidden then
        pcall(function() hidden = sapi:isAuthorHidden(name) == true end)
    end
    if hidden then return nil end
    return name
end

--- L'etichetta con l'autore, richiesta con il tasto destro fermo.
---
--- Si tiene qualche secondo e si rinnova a ogni fotogramma: NW_Tooltip vive di
--- affitto breve - due fotogrammi - perche' nasce per le cose che stanno sotto
--- il puntatore, e questa invece deve restare anche se il puntatore si sposta.
local TIP_MS = 3000

--- Un po' piu' larga del raggio della gomma: questa e' una domanda, non un
--- gesto che distrugge qualcosa, e puo' permettersi di essere generosa.
local ASK_PIXELS = 12

function I.showAuthor(mapUI, x, y)
    local name

    -- 1. Un'annotazione di vanilla - simbolo o biglietto.
    local sapi = symbols(mapUI)
    if sapi then
        local ok, index = pcall(function() return sapi:hitTest(x, y) end)
        if ok and index and index >= 0 then
            local sym
            pcall(function() sym = sapi:getSymbolByIndex(index) end)
            name = authorOf(mapUI, sym)
        end
    end

    -- 2. UN TRATTO A MANO LIBERA. Questa meta' mancava, e per i disegni la
    --    domanda non riceveva mai risposta: `hitTest` interroga l'elenco dei
    --    simboli di vanilla, e i nostri tratti li' non ci sono ne' ci
    --    andranno - sono roba nostra, in una lista nostra. La gomma lo sapeva
    --    gia' e li cerca in tutti e due i posti; questa domanda no.
    if not name then
        local wx, wy = worldAt(mapUI, x, y)
        local r = worldRadius(mapUI, ASK_PIXELS)

        -- Quelli degli altri, arrivati dal server: il nome se lo portano.
        if isWorldMap(mapUI) then
            local theirs = NW_NetClient.hit(wx, wy, r)
            if theirs then name = theirs.author end
        end

        -- I propri. In rete si risponde col proprio nome, come farebbe vanilla
        -- per un simbolo nostro. Da soli non si risponde: non c'e' nessun
        -- altro, e "scritto da te" e' una frase che non serve a niente.
        if not name and isClient() then
            local st = I.state(mapUI)
            for i = #st.strokes, 1, -1 do
                if NW_Brush.hits(st.strokes[i], wx, wy, r) then
                    pcall(function() name = playerOf(mapUI):getUsername() end)
                    break
                end
            end
        end
    end

    if not name or name == "" then return false end

    local st = I.state(mapUI)
    st.tip = {
        text = getText("IGUI_NW_ShareBy") .. " " .. name,
        x = mapUI:getAbsoluteX() + x,
        y = mapUI:getAbsoluteY() + y,
        until_ = (getTimestampMs and getTimestampMs() or 0) + TIP_MS,
    }
    return true
end

--- Tiene in vita l'etichetta finche' non scade. La chiama il disegno, che e'
--- l'unico posto che gira a ogni fotogramma.
local function keepTip(mapUI)
    local st = mapUI.nwStrokes
    local tip = st and st.tip
    if not tip then return end
    local now = getTimestampMs and getTimestampMs() or 0
    if now > tip.until_ then
        st.tip = nil
        NW_Tooltip.hide()
        return
    end
    NW_Tooltip.show(tip.text, tip.x, tip.y, 1, 1)
end

--- Chiude lo spostamento. Torna vero se la vista si e' mossa davvero: solo
--- allora il clic e' stato nostro, e chi ci sta sotto - il menu di debug degli
--- amministratori, per dirne uno - non lo deve vedere.
---
--- Se invece non si e' mossa, il destro non era un trascinamento: era una
--- domanda, e la domanda su un'annotazione e' "chi l'ha messa qui".
function I.panUp(mapUI)
    local st = mapUI.nwStrokes
    local p = st and st.pan
    if not p then return false end
    st.pan = nil
    if p.moved then return true end
    -- Fermo: e' una domanda. Se sotto c'e' un'annotazione si risponde con il
    -- nome di chi l'ha messa, e il clic e' nostro; se non c'e' niente si
    -- restituisce il gesto a vanilla, che ci tiene il menu dell'amministratore.
    return I.showAuthor(mapUI, p.x, p.y)
end

-- ---------------------------------------------------------------------------
-- Erase: strokes and symbols alike
-- ---------------------------------------------------------------------------

function I.eraseAt(mapUI, x, y)
    local st = I.state(mapUI)
    local wx, wy = worldAt(mapUI, x, y)
    local r = worldRadius(mapUI, ERASE_PIXELS)

    local gone = false
    local removed = {}
    for i = #st.strokes, 1, -1 do
        if NW_Brush.hits(st.strokes[i], wx, wy, r) then
            removed[#removed + 1] = { list = st.strokes, entry = st.strokes[i], at = i }
            -- Se era spartito, va tolto anche agli altri. Il server sa che e'
            -- nostro e lo toglie dal deposito del mondo.
            if isWorldMap(mapUI) then
                NW_NetClient.unshareStroke(playerOf(mapUI), st.strokes[i])
            end
            table.remove(st.strokes, i)
            gone = true
        end
    end

    -- Il tratto di un altro: si CHIEDE di toglierlo, e risponde il server.
    -- Qui non si sa niente di fazioni e di livelli d'accesso, e va bene cosi':
    -- se chi cancella ne ha il diritto lo dice quella meta', non questa. Se non
    -- ce l'ha, il tratto resta dov'e' e la gomma passa oltre senza fare storie.
    if isWorldMap(mapUI) then
        local theirs = NW_NetClient.hit(wx, wy, r)
        if theirs then
            NW_NetClient.removeRemote(theirs.id)
            NW_Sound.erase(playerOf(mapUI))
        end
    end
    NW_Undo.pushRemove(mapUI, removed, function() I.save(mapUI, true) end, st.erasing)
    if gone then
        I.save(mapUI)
        NW_Sound.erase(playerOf(mapUI))
    end

    -- Symbols and notes belong to vanilla, so they are removed through its API:
    -- that is what keeps the removal saved and synced.
    local sapi = symbols(mapUI)
    if not sapi then return end
    local ok, index = pcall(function() return sapi:hitTest(x, y) end)
    if ok and index and index >= 0 then
        pcall(function()
            local sym = sapi:getSymbolByIndex(index)
            -- L'annotazione di un altro non si cancella (mayModify). La gomma
            -- passa oltre in silenzio, come fa vanilla: un rumore o un
            -- messaggio direbbero "hai sbagliato tu", e non e' vero.
            if sym and mayModify(sym) then
                if sapi.sendRemoveSymbol then sapi:sendRemoveSymbol(sym) end
                sapi:removeSymbol(sym)
                NW_Sound.erase(playerOf(mapUI))
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Resize: drag an element bigger or smaller
-- ---------------------------------------------------------------------------

--- L'annotazione sotto il puntatore, se la si puo' toccare.
---
--- Il filtro sta qui e non nel gesto perche' da qui passano tutti e tre: il
--- ridimensionamento, il riquadro che lo annuncia, e quindi anche quello che il
--- giocatore si aspetta di poter fare.
local function grabSymbol(mapUI, x, y)
    local sapi = symbols(mapUI)
    if not sapi then return nil end
    local ok, index = pcall(function() return sapi:hitTest(x, y) end)
    if not (ok and index and index >= 0) then return nil end
    local ok2, sym = pcall(function() return sapi:getSymbolByIndex(index) end)
    if not (ok2 and sym) then return nil end
    if not mayModify(sym) then return nil end
    return sym
end

local function distanceTo(mapUI, sym, x, y)
    local sx = api(mapUI):worldToUIX(sym:getWorldX(), sym:getWorldY())
    local sy = api(mapUI):worldToUIY(sym:getWorldX(), sym:getWorldY())
    return math.max(4, math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2))
end

function I.beginResize(mapUI, x, y)
    local sym = grabSymbol(mapUI, x, y)
    if not sym then return false end
    local st = I.state(mapUI)
    st.resize = {
        sym = sym,
        scale0 = sym:getScale(),
        dist0 = distanceTo(mapUI, sym, x, y),
    }
    return true
end

--- What the mouse is over while a tool that acts on elements is armed, so the
--- box shows before the gesture starts rather than only during it.
function I.hoverResize(mapUI, x, y)
    local st = I.state(mapUI)
    if st.resize then return end
    st.hover = grabSymbol(mapUI, x, y)
end

--- Tools that point at something already on the map. They all get the box, so
--- "what am I about to touch" is answered the same way every time.
local TARGETING = { edit = true, erase = true, move = true, rotate = true }

--- Vanilla keeps what the mouse is over as an index on symbolsUI, and keeps it
--- current even for its own tools - which is how move and rotate get the box
--- without our code ever seeing their mouse events.
local function hovered(mapUI)
    local st = mapUI.nwStrokes
    if st and st.hover then return st.hover end
    local sui = mapUI.symbolsUI
    local sapi = symbols(mapUI)
    if not (sui and sapi) then return nil end
    local idx = sui.mouseOverSymbol or sui.mouseOverNote
    if not idx or idx < 0 then return nil end
    local ok, sym = pcall(function() return sapi:getSymbolByIndex(idx) end)
    if not (ok and sym) then return nil end
    -- Anche qui: niente riquadro su quello che non si puo' toccare. Vanilla
    -- tiene aggiornati questi due indici per i suoi strumenti senza filtrarli
    -- per noi, quindi il filtro va rifatto da questa parte.
    if not mayModify(sym) then return nil end
    return sym
end

function I.dragResize(mapUI, x, y)
    local st = I.state(mapUI)
    local r = st.resize
    if not r then return false end
    -- Scale follows the distance from the symbol's own centre: drag away to
    -- grow, towards it to shrink. No handles to find, no dialog to open.
    local factor = distanceTo(mapUI, r.sym, x, y) / r.dist0
    local s = math.max(MIN_SCALE, math.min(MAX_SCALE, r.scale0 * factor))
    pcall(function() r.sym:setScale(s) end)
    return true
end

function I.endResize(mapUI)
    local st = I.state(mapUI)
    if not st.resize then return false end
    local sapi = symbols(mapUI)
    if sapi and sapi.sendModifySymbol then
        pcall(function() sapi:sendModifySymbol(st.resize.sym) end)
    end
    -- LA MISURA SCELTA DIVENTA QUELLA DI PARTENZA. Chi ridimensiona un simbolo
    -- lo fa quasi sempre perche' alla misura di vanilla non gli andava bene, e
    -- rifarlo a ogni simbolo nuovo era la parte noiosa del lavoro. Si ricorda
    -- come multiplo della misura di vanilla, un numero per i simboli e uno per i
    -- biglietti, finche' non se ne ridimensiona un altro.
    pcall(function()
        local sym = st.resize.sym
        local kind = sym:isText() and "note" or "sym"
        NW.setLastSize("map", kind, sym:getScale() / ISMap.SCALE)
    end)
    st.resize = nil
    return true
end

-- ---------------------------------------------------------------------------
-- Un segno appena posato: misura e prospettiva
-- ---------------------------------------------------------------------------

--- Veste un simbolo o un biglietto appena nato. Lo chiamano tutti e due i modi
--- di posarne uno - il biglietto nostro (qui sotto) e il simbolo di vanilla
--- (NW_Map, attorno ad AddSymbol) - cosi' le due regole stanno in un posto solo.
---
--- `kind` e' "sym" o "note".
---
--- LA PROSPETTIVA E' DEL SEGNO, NON DELLA MAPPA. `setMatchPerspective` e' lo
--- stesso flag che vanilla mette su ogni simbolo dal suo dialogo "Adatta alla
--- prospettiva": acceso, il segno si disegna steso sul piano della mappa quando
--- la vista e' isometrica; spento resta dritto come un cartello. Il tasto del
--- pannello decide come nascono i segni DA ADESSO: quelli gia' posati si tengono
--- la prospettiva con cui sono nati. Il flag sta nel salvataggio del simbolo
--- (WorldMapBaseSymbol.save/load, letto nel bytecode) e parte con
--- sendModifySymbol insieme al resto, quindi in rete lo vede steso anche chi non
--- ha la mod accesa allo stesso modo.
---
--- Una versione di prova lo applicava invece a tutti i simboli a ogni apertura:
--- cambiava come si vedevano tutti, e un segno fatto dritto non restava dritto.
function I.dressMark(mapUI, sym, kind)
    if not sym then return end
    pcall(function() sym:setScale(ISMap.SCALE * NW.lastSize("map", kind)) end)
    if isWorldMap(mapUI) then
        pcall(function() sym:setMatchPerspective(NW.marksFollowPerspective()) end)
    end
end

-- ---------------------------------------------------------------------------
-- Note: typed on the map
-- ---------------------------------------------------------------------------

--- Il carattere con cui il livello di testo disegna i biglietti.
---
--- LO STILE SI CHIEDE ALLA v3, NON A `mapUI.mapAPI`. Sulla mappa del mondo le
--- due coincidono; su una mappa di carta `mapUI.mapAPI` e' la v1 (ISMap:
--- `getAPIv1()`), e il livello che torna da li' non ha `getFont`. Chiamarglielo
--- non dava nil: dava "Tried to call nil", che in Kahlua e' un'eccezione Java
--- che sfonda il pcall (lezione 33) - e scrivere un biglietto su una mappa
--- annotata finiva nel log invece che sulla carta.
---
--- Vanilla prende la stessa strada da cui la prendiamo adesso: il pannello dei
--- simboli si tiene il suo `styleAPI`, ricavato dalla v3.
local function noteFont(mapUI)
    local font = UIFont.Handwritten
    local layer

    pcall(function()
        local sui = mapUI.symbolsUI
        local style = sui and sui.styleAPI
        local id = sui and sui.symbolsAPI and sui.symbolsAPI:getDefaultTextLayerID()
        if style and id then layer = style:getLayerByName(id) end
    end)

    -- Il metodo si CHIEDE prima di chiamarlo: su un livello che non ce l'ha,
    -- chiamarlo non torna nil, fa saltare tutto.
    if layer and layer.getFont then
        local ok, f = pcall(function() return layer:getFont() end)
        if ok and f then font = f end
    end
    return font
end


function I.beginNote(mapUI, x, y)
    local sapi = symbols(mapUI)
    if not sapi then return false end

    local layerID = sapi:getDefaultTextLayerID()
    local ink = NW.inkById(mapUI.nwInkId or "black")
    local wx, wy = worldAt(mapUI, x, y)
    if NW_NetClient and NW_NetClient.verbose then
        print("NW_Ink: biglietto, si apre il campo. livello=" .. tostring(layerID))
    end

    -- Uno solo posto che sa da dove viene il carattere, e sa anche che sulla
    -- mappa di carta la strada e' un'altra.
    local font = noteFont(mapUI)

    NW_NoteEntry.open(mapUI:getAbsoluteX() + x, mapUI:getAbsoluteY() + y, 220,
        font, ink,
        function(text, scale, angle)
            -- Il testo com'e' USCITO dal campo, prima che lo tocchi chiunque
            -- altro. "Il biglietto diventa tutti punti interrogativi" ha due
            -- cause opposte - il campo raccoglie male quello che si scrive,
            -- oppure lo raccoglie bene e si perde dopo, nel carattere o nel
            -- giro di rete - e producono lo stesso schermo. Qui si vede quale
            -- delle due: se la riga mostra le lettere giuste, il campo e'
            -- innocente.
            if NW_NetClient and NW_NetClient.verbose then
                print("NW_Ink: biglietto \"" .. tostring(text) .. "\" ("
                    .. tostring(#tostring(text)) .. " byte), carattere "
                    .. tostring(font))
            end
            -- I PUNTI INTERROGATIVI NON SONO UN DIFETTO DI QUESTA RIGA.
            --
            -- Un biglietto che compare come "????" e' quasi sempre un
            -- personaggio ANALFABETA: il gioco rappresenta cosi' quello che un
            -- analfabeta scrive e legge, ed e' una sua funzione, non un guasto
            -- nostro (NW_Tools.isIlliterate lo sa gia').
            --
            -- E IL BIGLIETTO E' TESTO, NON UNA CHIAVE. Qui c'era
            -- `addUntranslatedText`, che per il gioco vuol dire "chiave da
            -- tradurre": a ogni misura e a ogni clic il testo passava da
            -- Translator.getText, e un "%" scritto dal giocatore faceva cadere
            -- hitTest con UnknownFormatConversionException. Vanilla per un
            -- biglietto normale usa `addTranslatedText`, e adesso anche noi
            -- (NW_MapDoc.addNote, dove sta il perche' letto nel bytecode). I
            -- biglietti salvati prima col "%" li ripara NW_MapDoc.repairNotes.
            local sym = NW_MapDoc.addNote(sapi, text, layerID, wx, wy)
            if sym then
                NW_Sound.note(playerOf(mapUI))
                sym:setAnchor(0.0, 0.5)
                sym:setRotation(0.0)
                sym:setRGBA(ink.r, ink.g, ink.b, 1.0)
                -- La misura dell'ultimo biglietto ridimensionato e la
                -- prospettiva della mappa: tutti e due in un posto solo.
                I.dressMark(mapUI, sym, "note")
                -- Misura e angolo scelti mentre si scriveva (NW_Placing). La
                -- misura diventa anche quella del prossimo biglietto, come per
                -- lo strumento Modifica.
                if NW_Placing and NW_Placing.enabled() then
                    if scale and scale > 0 then
                        pcall(function() sym:setScale(ISMap.SCALE * scale) end)
                        NW.setLastSize("map", "note", scale)
                    end
                    if angle and angle ~= 0 then
                        pcall(function() sym:setRotation(angle) end)
                    end
                end
                if sym.setUserDefined then pcall(function() sym:setUserDefined(true) end) end
                -- La scelta di condivisione vale per tutto quello che si posa,
                -- e va messa PRIMA di spedire: sendModifySymbol manda quello
                -- che c'e' adesso, e un biglietto spedito privato resta privato
                -- anche se un attimo dopo gli si cambia idea.
                NW_Share.applyTo(sym, playerOf(mapUI))
                if sapi.sendModifySymbol then pcall(function() sapi:sendModifySymbol(sym) end) end
            end
        end)
    return true
end

-- ---------------------------------------------------------------------------
-- Mouse
-- ---------------------------------------------------------------------------

--- Una fotografia dello stato, per il log. Serve a una domanda sola: quando un
--- gesto non fa niente, dov'e' che si e' fermato.
---
--- E' dietro `NW_NetClient.verbose` come tutto il resto del parlato, quindi in
--- una versione pubblicata non stampa niente.
--- Se le annotazioni sono spente nelle impostazioni della mappa.
---
--- E' un'opzione di VANILLA ("Symbols"), e sta anche nel nostro pannello delle
--- impostazioni perche' quelle caselle sono le sue. Spenta, tutto quello che si
--- posa diventa invisibile: il simbolo nasce, si puo' ancora prendere e
--- spostare, ma non lo disegna nessuno. Da fuori sembra che la mod abbia smesso
--- di funzionare, ed e' costata una serata: adesso lo dice il log.
local function symbolsShown(mapUI)
    local on
    pcall(function()
        local a = api(mapUI)
        for i = 1, a:getOptionCount() do
            local o = a:getOptionByIndex(i - 1)
            if o:getName() == "Symbols" then on = o:getValue() end
        end
    end)
    return on
end

function I.diag(mapUI, quando)
    if not (NW_NetClient and NW_NetClient.verbose and mapUI) then return end
    local sapi = symbols(mapUI)
    local sui = mapUI.symbolsUI
    local n, tool, zoom = -1, tostring(mapUI.nwTool), -1
    pcall(function() n = sapi:getSymbolCount() end)
    pcall(function() zoom = api(mapUI):getZoomF() end)
    local st = mapUI.nwStrokes
    print("NW_Ink [" .. tostring(quando) .. "]: strumento=" .. tool
        .. " nostro=" .. tostring(I.owns(mapUI))
        .. " | simboli: api=" .. tostring(sapi ~= nil) .. " n=" .. tostring(n)
        .. " tavola=" .. tostring(sui and sui.buttonList and #sui.buttonList or -1)
        .. " scelto=" .. tostring(sui and sui.selectedSymbol ~= nil)
        .. " strumentoVanilla=" .. tostring(sui and sui.currentTool ~= nil)
        .. " | tratti=" .. tostring(st and st.strokes and #st.strokes or -1)
        .. " | zoom=" .. string.format("%.2f", zoom)
        .. " notte=" .. tostring(mapUI.nwDark) .. "/" .. tostring(NW.darkMap())
        .. " | opzione Simboli=" .. tostring(symbolsShown(mapUI)))
end

function I.onDown(mapUI, x, y)
    local tool = mapUI.nwTool
    local st = I.state(mapUI)

    if tool == "erase" then
        st.erasing = {}
        I.eraseAt(mapUI, x, y)
        return true
    end
    if tool == "edit" then
        return I.beginResize(mapUI, x, y)
    end

    -- NIENTE PENNA, NIENTE SEGNO. L'inchiostro lo mette il pannello guardando
    -- nella borsa, e lo toglie quando l'ultima penna esce: prima qui si ripiegava
    -- sul nero (`nwInkId or "black"`), cioe' si disegnava anche senza niente in
    -- mano - e con il colore dell'ultima penna posata, se la matita era rimasta
    -- scelta. Il clic si consuma lo stesso: lasciarlo passare farebbe scivolare
    -- la mappa sotto uno strumento che l'utente crede di tenere in mano.
    if not mapUI.nwInkId then return true end

    -- La partita ha spento il disegno a mano libera (opzione sandbox). Il
    -- pannello non offre piu' la penna, ma lo strumento poteva essere in mano
    -- nel momento in cui l'admin ha cambiato l'opzione.
    if tool == "draw" and not NW_Net.freehandAllowed() then return true end

    if tool == "note" then
        return I.beginNote(mapUI, x, y)
    end

    -- La penna e' ferma: si alza il cartello e il clic finisce qui. Torna vero
    -- perche' il gesto e' stato gestito - lasciandolo passare, la mappa
    -- comincerebbe a spostarsi sotto una penna che non scrive.
    if NW_MapDoc.isFull(mapUI) then
        notice(mapUI)
        return true
    end

    local ink = NW.inkById(mapUI.nwInkId or "black")
    local wx, wy = worldAt(mapUI, x, y)
    st.active = NW_Brush.newStroke(mapUI.nwWidth or NW.BRUSH.DEFAULT, ink.r, ink.g, ink.b)
    -- ANCHE L'ID DELL'INCHIOSTRO, non solo il colore sciolto. Nel deposito si
    -- salva l'id (`c`), che e' l'unica cosa che sopravvive a una riapertura:
    -- senza, un tratto rosso tornava nero. La pagina lo fa gia' cosi'
    -- (NW_PageInk: page.live.c = page.inkId).
    st.active.c = mapUI.nwInkId or "black"
    NW_Brush.addPoint(st.active, wx, wy)
    return true
end

function I.onMove(mapUI, x, y)
    local st = I.state(mapUI)
    if mapUI.nwTool == "edit" and not st.resize then I.hoverResize(mapUI, x, y) end
    if st.erasing then I.eraseAt(mapUI, x, y) return true end
    if st.resize then return I.dragResize(mapUI, x, y) end
    if not st.active then return false end
    local wx, wy = worldAt(mapUI, x, y)
    NW_Brush.addPoint(st.active, wx, wy)
    return true
end

function I.onUp(mapUI, x, y)
    local st = I.state(mapUI)
    if st.erasing then st.erasing = false return true end
    if st.resize then return I.endResize(mapUI) end
    if not st.active then return false end
    local wx, wy = worldAt(mapUI, x, y)
    NW_Brush.addPoint(st.active, wx, wy)
    NW_Brush.endStroke(st.active, worldEpsilon(mapUI, st.active))
    local entry = st.active
    st.active = nil
    keepAndShare(mapUI, entry)
    return true
end

--- True while a gesture of ours has the mouse.
local function inGesture(st)
    return st and (st.erasing or st.resize or st.active or st.pan) and true or false
end

--- Ends whatever was in progress, wherever the button came up.
---
--- Releasing the button off the map - over our own panel, or outside the
--- window - never reaches ISWorldMap:onMouseUp, so the gesture stayed open:
--- erasing kept erasing, the stroke kept drawing, and every later click was
--- swallowed. That is what made panning stop working and the print media on the
--- map stop opening, seemingly at random.
function I.cancel(mapUI)
    local st = mapUI.nwStrokes
    if not inGesture(st) then return false end
    st.pan = nil
    st.erasing = false
    if st.resize then I.endResize(mapUI) end
    if st.active then
        NW_Brush.endStroke(st.active, worldEpsilon(mapUI, st.active))
        local entry = st.active
        st.active = nil
        keepAndShare(mapUI, entry)
    end
    return true
end

--- The belt to cancel()'s braces, run once a frame.
---
--- onMouseUpOutside is not guaranteed either: the window can lose focus, or the
--- element can be rebuilt mid-drag. Asking the engine whether the button is
--- still down costs nothing and closes every remaining way to leave a gesture
--- hanging.
function I.checkStuck(mapUI)
    local st = mapUI.nwStrokes
    if not inGesture(st) then return end
    -- Lo spostamento sta sul tasto destro e ha il suo bottone da guardare: con
    -- il solo controllo sul sinistro restava aperto per sempre appena il destro
    -- si alzava fuori dalla mappa.
    if st.pan and not isMouseButtonDown(1) then st.pan = nil end
    if not inGesture(st) then return end
    if isMouseButtonDown(0) then return end
    if st.pan then return end
    I.cancel(mapUI)
end


--- The selection box: drawn from the symbol's own extents, so it follows
--- whatever is grabbed at whatever scale.
---
--- A text note is not a square. It used to get one anyway - the same 32-unit
--- box a picture symbol gets - so on the map a long note was wrapped by a small
--- square in its middle, while on a page the very same note got a frame around
--- its letters. One gesture cannot have two shapes. A note is measured: anchored
--- left and centred vertically, which is how it is laid down (setAnchor 0, 0.5).
local function drawBox(mapUI, sym, r, g, b, alpha)
    if not sym then return end
    alpha = alpha or 1.0
    local a = api(mapUI)
    local cx = a:worldToUIX(sym:getWorldX(), sym:getWorldY())
    local cy = a:worldToUIY(sym:getWorldX(), sym:getWorldY())
    local s = (sym:getScale() or 1) * (a:getWorldScale() or 1)

    local texture = true
    local okT, res = pcall(function() return sym:isTexture() end)
    if okT and res ~= nil then texture = res end

    local x0, y0, x1, y1
    if texture then
        -- No width is exposed for a picture symbol, so the box is sized from its
        -- scale against the map scale: the same number the renderer draws with.
        local half = math.max(10, 16 * s)
        x0, y0, x1, y1 = cx - half, cy - half, cx + half, cy + half
    else
        local text = ""
        local t = NW_MapDoc.noteText(sym)
        if t then text = tostring(t):gsub("\n", " "):gsub("<br>", " ") end
        local font = noteFont(mapUI)
        local tm = getTextManager()
        local w = math.max(12, tm:MeasureStringX(font, text) * s)
        local h = math.max(8, tm:getFontHeight(font) * s)
        x0, y0 = cx - 3, cy - h / 2 - 3
        x1, y1 = cx + w + 3, cy + h / 2 + 3
    end
    local half = math.min(x1 - x0, y1 - y0) / 2
    mapUI:drawRectBorder(x0, y0, x1 - x0, y1 - y0, 0.9 * alpha, r, g, b)
    -- Corner ticks, so it reads as a handle and not as a stray rectangle.
    local t = math.max(4, half * 0.28)
    -- top-left
    mapUI:drawRect(x0, y0, t, 2, alpha, r, g, b)
    mapUI:drawRect(x0, y0, 2, t, alpha, r, g, b)
    -- top-right
    mapUI:drawRect(x1 - t, y0, t, 2, alpha, r, g, b)
    mapUI:drawRect(x1 - 2, y0, 2, t, alpha, r, g, b)
    -- bottom-left
    mapUI:drawRect(x0, y1 - 2, t, 2, alpha, r, g, b)
    mapUI:drawRect(x0, y1 - t, 2, t, alpha, r, g, b)
    -- bottom-right
    mapUI:drawRect(x1 - t, y1 - 2, t, 2, alpha, r, g, b)
    mapUI:drawRect(x1 - 2, y1 - t, 2, t, alpha, r, g, b)
end

--- Il cartello della mappa piena, in cima e al centro.
---
--- Sta sulla MAPPA e non nel pannello per una ragione sola: e' li' che la mano
--- stava disegnando quando non e' successo niente, ed e' li' che si guarda.
--- Sparisce da solo dopo qualche secondo, e tornando a premere si rialza.
local function drawNotice(mapUI)
    local at = mapUI.nwNoticeAt
    if not at then return end
    local now = getTimestampMs and getTimestampMs() or 0
    local left = NOTICE_MS - (now - at)
    if left <= 0 then mapUI.nwNoticeAt = nil return end

    -- L'ultimo mezzo secondo si dissolve: un cartello che sparisce di colpo
    -- sembra un difetto di disegno.
    local alpha = math.min(1, left / 500)
    local text = getText("IGUI_NW_MapFull")
    local font = UIFont.Medium
    local tm = getTextManager()
    local w = tm:MeasureStringX(font, text)
    local h = tm:getFontHeight(font)
    local pad = 12
    local x = math.floor((mapUI.width - w) / 2)
    local y = 24

    mapUI:drawRect(x - pad, y - pad / 2, w + pad * 2, h + pad,
        0.72 * alpha, 0.08, 0.08, 0.09)
    mapUI:drawRectBorder(x - pad, y - pad / 2, w + pad * 2, h + pad,
        0.55 * alpha, NW_Style.close.r, NW_Style.close.g, NW_Style.close.b)
    mapUI:drawText(text, x, y, NW_Style.text.r, NW_Style.text.g, NW_Style.text.b,
        alpha, font)
end

--- Drawn over the map. Called from prerender: children paint between prerender
--- and render, so ink drawn in render would cover the panel.
function I.render(mapUI)
    local a = api(mapUI)

    -- L'etichetta con l'autore, se qualcuno l'ha chiesta col destro.
    keepTip(mapUI)

    -- L'inchiostro c'e' solo se qualcuno ha disegnato; il riquadro di selezione
    -- deve esserci comunque.
    --
    -- Prima questa funzione usciva subito quando `nwStrokes` era nil, cioe'
    -- finche' non si era disegnato almeno un tratto nella sessione: prendendo
    -- Sposta o Ruota su una mappa mai disegnata, il riquadro arancione non
    -- compariva. Sulla pagina compare sempre, e le due mani devono somigliarsi.
    local st = I.state(mapUI)
    if st then
        local toX = function(wx, wy) return a:worldToUIX(wx, wy) end
        local toY = function(wx, wy) return a:worldToUIY(wx, wy) end
        -- Quanti pixel vale adesso un punto di spessore: uguale per tutti i
        -- tratti, chiesto una volta per fotogramma invece di una per tratto.
        local pen = penScale(mapUI)
        -- Prima quelli degli altri, poi i propri: chi disegna vede sempre la
        -- sua mano sopra, che e' quello che si aspetta mentre la muove.
        if isWorldMap(mapUI) then
            for _, s in ipairs(NW_NetClient.strokes()) do
                NW_Brush.render(mapUI, s, toX, toY, pen)
            end
        end
        for _, s in ipairs(st.strokes) do NW_Brush.render(mapUI, s, toX, toY, pen) end
        if st.active then NW_Brush.render(mapUI, st.active, toX, toY, pen) end
    end

    -- The one selection box on the map. Vanilla's own outline is silenced in
    -- NW_Map precisely so that this is the only thing drawn around a symbol.
    -- Erasing keeps a warning colour: it is the one gesture that destroys.
    local c = NW_Style.accent
    if mapUI.nwTool == "erase" then c = NW_Style.close end

    if st and st.resize then
        drawBox(mapUI, st.resize.sym, c.r, c.g, c.b, 1.0)   -- in hand
    elseif TARGETING[mapUI.nwTool or ""] then
        drawBox(mapUI, hovered(mapUI), c.r, c.g, c.b, 0.55) -- under the mouse
    end

    drawNotice(mapUI)
end
