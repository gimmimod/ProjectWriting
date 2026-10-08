--[[ ============================================================================
    NW_PageInk - cosa fa il mouse sulla pagina.

    Le stesse abitudini della mappa, con una regola in piu' che la mappa non ha:
    UNA FACCIATA E' UN MONDO CHIUSO. Un tratto comincia dentro una facciata e li'
    resta, anche se la mano esce; un simbolo non si posa sulla rilegatura; il
    quaderno aperto non e' un foglio unico ma due, e la spirale in mezzo non e'
    carta. E' NW_Page:areaAt a dirlo, tornando nil dove non si scrive.

    IL RIQUADRO DI SELEZIONE E' QUELLO DELLA MAPPA, stessa forma e stessi
    colori: cornice piu' quattro angoli, arancione per prendere e rosso per
    cancellare, pieno su quello in mano e velato su quello sotto il cursore.
    Sulla mappa lo disegna NW_Ink.drawBox, e le due mani devono somigliarsi: chi
    ha imparato a spostare un simbolo sulla mappa non deve reimparare qui.

    LA GOMMA SUL TESTO E' UN'ALTERNATIVA, non l'unica strada: cancella una riga
    per volta, e serve quando si ha in mano la gomma per altro. Il modo normale
    di correggere e' quello di sempre - si prende la penna, si seleziona col
    trascinamento e si cancella da tastiera - perche' li' comanda il riquadro di
    scrittura di vanilla, che quelle cose le sa fare.

    Tutto quello che si posa finisce nell'oggetto nello stesso istante. Non c'e'
    un tasto per salvare perche' non c'e' un momento in cui non e' salvato: e'
    NW_Doc a tenere il conto, e l'unica cosa rimandata e' l'avviso al server.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Brush"
require "NeatWriting/NW_Sound"
require "NeatWriting/NW_Undo"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Net"
require "NeatWriting/NW_Doc"
require "NeatWriting/NW_Layouts"
require "NeatWriting/NW_Style"
require "NeatWriting/UI/NW_NoteEntry"
require "NeatWriting/UI/NW_Writer"

NW_PageInk = NW_PageInk or {}
local I = NW_PageInk

local ERASE_PX = 11        -- meta' lato della gomma, in pixel di schermo
local GRAB_PX  = 20        -- quanto vicino bisogna essere per prendere qualcosa
local SCALE_PX = 220       -- quanti pixel di trascinamento raddoppiano un simbolo
local TURN_PX  = 2.0       -- gradi per pixel trascinato

--- Gli strumenti che lavorano sulla carta. Il testo no: quello ha il suo
--- cursore, e se lo prende NW_Page.
local OURS = {
    draw = true, erase = true, note = true, symbol = true,
    move = true, rotate = true, edit = true,
}

--- Quelli che mirano a qualcosa di gia' posato, e quindi mostrano il riquadro.
local TARGETING = { move = true, rotate = true, edit = true, erase = true }

function I.owns(page)
    return page.editable and OURS[page.tool or ""] == true
end

local function ink(page)
    return NW.inkById(page.inkId or "black")
end

-- ---------------------------------------------------------------------------
-- Trovare quello che c'e' gia'
-- ---------------------------------------------------------------------------

--- L'ingombro di un elemento, in unita' di facciata.
---
--- Un simbolo e' un quadrato centrato sul suo punto; un biglietto e' il suo
--- testo, che dal punto va a destra. Prima erano tutti e due un cerchietto
--- attorno al punto, ed e' il motivo per cui i biglietti non si cancellavano:
--- il punto di un biglietto e' il suo angolo alto-sinistro, e per prenderlo
--- bisognava indovinare l'angolo invece di toccare le lettere.
local function bounds(page, it, kind)
    if kind == "sym" then
        local h = (it.s or 40) / 2
        return it.x - h, it.y - h, it.x + h, it.y + h
    end
    -- Per un biglietto `s` non e' una misura ma un ingrandimento: il testo e'
    -- sempre nella stessa grafia, e a cambiare e' quanto la si ingrandisce.
    local k, zoom = page:k(), it.s or 1
    local w = getTextManager():MeasureStringX(page.font, it.t or "") * zoom / k
    local h = (page.lineH or 12) * zoom / k
    return it.x, it.y, it.x + math.max(w, 8), it.y + h
end

--- L'elemento sotto un punto, i piu' recenti per primi: chi ha posato per
--- ultimo si riprende per primo.
---
--- Simboli e biglietti si prendono allo stesso modo, e da NW_TextLayer in poi si
--- girano e si scalano tutti e due: sulla mappa e' cosi', e due mani diverse per
--- lo stesso gesto sono due cose da imparare invece di una.
local function pick(page, n, pageIdx, ax, ay, slack, kinds)
    for _, kind in ipairs(kinds or { "note", "sym" }) do
        local list = NW_Doc.list(page.item, pageIdx, kind, false)
        if list then
            for i = #list, 1, -1 do
                local it = list[i]
                local x0, y0, x1, y1 = bounds(page, it, kind)
                if ax >= x0 - slack and ax <= x1 + slack
                    and ay >= y0 - slack and ay <= y1 + slack then
                    return { kind = kind, list = list, index = i, item = it, n = n }
                end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- La gomma
-- ---------------------------------------------------------------------------

--- Cancella, e dice cosa ha portato via: la pila del revert deve poterlo
--- rimettere dov'era, e per farlo le serve la voce e il posto che aveva.
local function erase(page, n, pageIdx, ax, ay, radius)
    -- L'etichetta del gesto: tutte le passate della stessa strisciata di gomma
    -- finiscono in un solo passo indietro.
    local gesture = page.erasing
    local gone = false
    local removed = {}

    local strokes = NW_Doc.list(page.item, pageIdx, "ink", false)
    if strokes then
        for i = #strokes, 1, -1 do
            if NW_Brush.hits({ pts = strokes[i].p }, ax, ay, radius) then
                removed[#removed + 1] = { list = strokes, entry = strokes[i], at = i }
                table.remove(strokes, i)
                gone = true
            end
        end
    end

    -- Con la stessa tolleranza con cui si prende un elemento per spostarlo:
    -- un clic vicino cancella, non serve centrarlo.
    local hit = pick(page, n, pageIdx, ax, ay, radius)
    if hit then
        removed[#removed + 1] = { list = hit.list, entry = hit.list[hit.index], at = hit.index }
        table.remove(hit.list, hit.index)
        gone = true
    end
    NW_Undo.pushRemove(page, removed, nil, gesture)

    -- Il testo si cancella una riga per volta, ed e' l'alternativa: quando il
    -- riquadro di scrittura e' aperto si seleziona col trascinamento e si
    -- cancella da tastiera, come in qualunque editor.
    if not gone then
        local row = page:lineAt(n, ax, ay)
        if row then gone = page:eraseLine(n, row) end
    end
    return gone
end

-- ---------------------------------------------------------------------------
-- I gesti
-- ---------------------------------------------------------------------------

--- Riapre un biglietto per correggerlo, esattamente dov'e'.
---
--- Ci si arriva con la penna da biglietti, cliccando su uno che c'e' gia': e' il
--- gesto piu' corto, e non ruba niente a Ridimensiona, che su un biglietto ha da
--- fare il suo mestiere. Svuotare il campo lo cancella.
function I.editNote(page, n, pageIdx, hit)
    local it = hit.item
    local k = page:k()
    local ux, uy = page:toUI(n, it.x, it.y)
    local x0, _, x1 = NW_Layouts.area(page.media, n)
    local room = math.floor((x1 - x0 - it.x) * k)
    NW_NoteEntry.open(page:getAbsoluteX() + ux, page:getAbsoluteY() + uy,
        math.max(80, room), page.font, NW.inkById(it.c or "black"),
        function(text)
            if text == "" then
                table.remove(hit.list, hit.index)
            else
                it.t = text
            end
            NW_Doc.touch(page.item, page.player, true)
        end, nil, it.t or "")
end

function I.press(page, x, y)
    if not I.owns(page) then return end
    local n, ax, ay = page:areaAt(x, y)
    if not n then return end
    local pageIdx = page:pageOf(n)
    if not pageIdx then return end

    local k = page:k()
    local tool = page.tool

    -- Scrivere, posare un simbolo e scrivere un biglietto vogliono una penna.
    -- Spostare, girare, ridimensionare e cancellare no: sono gesti su quello
    -- che c'e' gia'.
    if not page.inkId and (tool == "draw" or tool == "symbol" or tool == "note") then
        return
    end
    -- Disegno a mano libera spento dalla partita (opzione sandbox, NW_Net).
    if tool == "draw" and not NW_Net.freehandAllowed() then return end

    if tool == "draw" then
        page.live = NW_Brush.newStroke(math.max(0.5, page.brush / k))
        page.live.n = n
        page.live.page = pageIdx
        page.live.c = page.inkId
        NW_Brush.addPoint(page.live, ax, ay)

    elseif tool == "erase" then
        page.erasing = { n = n, page = pageIdx }
        if erase(page, n, pageIdx, ax, ay, ERASE_PX / k) then
            NW_Doc.touch(page.item, page.player)
            NW_Sound.erase(page.player)
        end

    elseif tool == "symbol" then
        if not page.symbol then return end
        local list = NW_Doc.list(page.item, pageIdx, "sym", true)
        local entry = {
            id = page.symbol.id, x = ax, y = ay,
            -- Alla misura dell'ultimo simbolo ridimensionato su un foglio.
            s = NW.SYMBOL_SIZE * NW.lastSize("page", "sym") / k, r = 0, c = page.inkId,
        }
        -- E l'angolo scelto con Shift + rotella mentre lo si teneva in mano.
        local P = rawget(_G, "NW_Placing")
        if P and P.enabled() and (P.pageAngle or 0) ~= 0 then entry.r = P.pageAngle end
        list[#list + 1] = entry
        NW_Undo.pushAdd(page, list, entry, function()
            NW_Doc.touch(page.item, page.player, true)
        end)
        NW_Doc.touch(page.item, page.player, true)
        NW_Sound.symbol(page.player)

    elseif tool == "note" then
        -- Cliccare con la penna da biglietti su un biglietto gia' scritto vuol
        -- dire correggerlo, non impilarne un altro sopra.
        local old = pick(page, n, pageIdx, ax, ay, 0, { "note" })
        if old then
            I.editNote(page, n, pageIdx, old)
            return
        end
        local ux, uy = page:toUI(n, ax, ay)
        local x0, _, x1 = NW_Layouts.area(page.media, n)
        -- Il biglietto si scrive verso destra: la larghezza e' quello che resta
        -- di facciata dal punto in cui si e' cliccato.
        local room = math.floor((x1 - x0 - ax) * k)
        local entryUI = NW_NoteEntry.open(page:getAbsoluteX() + ux, page:getAbsoluteY() + uy,
            math.max(80, room), page.font, ink(page),
            function(text, scale, angle)
                local list = NW_Doc.list(page.item, pageIdx, "note", true)
                local entry = { x = ax, y = ay, t = text, c = page.inkId }
                -- Ingrandito come l'ultimo biglietto ridimensionato, o come lo si
                -- e' scelto con Ctrl + rotella mentre lo si scriveva (NW_Placing);
                -- alla misura di partenza non si scrive niente, come prima.
                local P = rawget(_G, "NW_Placing")
                local size = NW.lastSize("page", "note")
                if P and P.enabled() and scale and scale > 0 then
                    size = scale
                    NW.setLastSize("page", "note", scale)
                end
                if math.abs(size - 1) > 0.001 then entry.s = size end
                if P and P.enabled() and angle and angle ~= 0 then entry.r = angle end
                list[#list + 1] = entry
                NW_Undo.pushAdd(page, list, entry, function()
                    NW_Doc.touch(page.item, page.player, true)
                end)
                NW_Doc.touch(page.item, page.player, true)
                NW_Sound.note(page.player)
            end)
        -- Il campo parte dalla misura dei biglietti dei fogli, non di quelli
        -- della mappa: sono due ricordi diversi (NW.lastSize).
        if entryUI then entryUI.scale = NW.lastSize("page", "note") end

    else   -- move, rotate, edit
        local hit = pick(page, n, pageIdx, ax, ay, GRAB_PX / k)
        if not hit then return end
        hit.page = pageIdx
        hit.grabUX, hit.grabUY = page:toUI(n, ax, ay)
        hit.startSize = hit.item.s or (hit.kind == "sym" and 40 or 1)
        hit.startAngle = hit.item.r or 0
        page.grab = hit
    end
end

--- Il tasto destro cancella quello che sta sotto, senza cambiare strumento.
---
--- La gomma resta la strada principale; questa e' la scorciatoia per chi ha in
--- mano Sposta o Ruota e vuole solo togliere di mezzo una cosa - cambiare
--- strumento, cancellare e tornare indietro sono tre gesti per uno solo.
function I.rightPress(page, x, y)
    if not page.editable then return end
    if not TARGETING[page.tool or ""] then return end
    local n, ax, ay = page:areaAt(x, y)
    if not n then return end
    local pageIdx = page:pageOf(n)
    if not pageIdx then return end

    local hit = pick(page, n, pageIdx, ax, ay, GRAB_PX / page:k())
    if not hit then return end
    table.remove(hit.list, hit.index)
    page.grab = nil
    NW_Doc.touch(page.item, page.player, true)
end

function I.drag(page, x, y)
    local k = page:k()

    if page.live then
        local n = page.live.n
        local _, ax, ay = page:areaAt(x, y)
        if not ax then
            -- La mano e' uscita dalla facciata: il tratto si ferma sul bordo
            -- invece di saltare dall'altra parte della piega.
            local x0, y0 = NW_Layouts.area(page.media, n)
            ax, ay = x / k - x0, y / k - y0
        end
        ax, ay = page:clamp(n, ax, ay)
        NW_Brush.addPoint(page.live, ax, ay)
        return
    end

    if page.erasing then
        local n, ax, ay = page:areaAt(x, y)
        if n == page.erasing.n and ax then
            if erase(page, n, page.erasing.page, ax, ay, ERASE_PX / k) then
                NW_Doc.touch(page.item, page.player)
            end
        end
        return
    end

    local g = page.grab
    if not g then return end

    if page.tool == "edit" then
        local f = 1 + (y - g.grabUY) / SCALE_PX
        if g.kind == "sym" then
            g.item.s = math.max(8 / k, math.min(400 / k, g.startSize * f))
        else
            -- Per un biglietto il numero e' un ingrandimento, non dei pixel:
            -- da meno di meta' a quattro volte, che sopra e sotto diventa
            -- illeggibile in due modi diversi.
            g.item.s = math.max(0.4, math.min(4.0, g.startSize * f))
        end

    elseif page.tool == "rotate" then
        -- Si gira trascinando in orizzontale, non calcolando l'angolo del mouse
        -- attorno al centro: quel secondo modo fa saltare il simbolo di colpo
        -- appena lo si prende da vicino al suo centro.
        g.item.r = (g.startAngle + (x - g.grabUX) * TURN_PX) % 360

    elseif page.tool == "move" then
        local _, ax, ay = page:areaAt(x, y)
        if not ax then
            local x0, y0 = NW_Layouts.area(page.media, g.n)
            ax, ay = x / k - x0, y / k - y0
        end
        ax, ay = page:clamp(g.n, ax, ay)
        g.item.x, g.item.y = ax, ay
    end
    -- Ruota e Ridimensiona su un biglietto non fanno niente, e non lo spostano:
    -- prima ci cadevano dentro e il biglietto saltava sotto il cursore.
end

function I.release(page, x, y)
    if page.live then
        local s = page.live
        page.live = nil
        NW_Brush.endStroke(s)
        -- Una passata di Chaikin qui e non a ogni frame: il tratto si smussa una
        -- volta sola, e quello che finisce nell'oggetto e' gia' quello che si
        -- vede. Il conto dei punti raddoppia, ma RDP ne aveva tolti tre quarti.
        s.pts = NW_Brush.smooth(s.pts, 1)
        if #s.pts >= 4 then
            local list = NW_Doc.list(page.item, s.page, "ink", true)
            local entry = { w = s.w, c = s.c, p = s.pts }
            list[#list + 1] = entry
            NW_Undo.pushAdd(page, list, entry, function()
                NW_Doc.touch(page.item, page.player, true)
            end)
            NW_Doc.touch(page.item, page.player, true)
        end
    end
    if page.erasing then
        page.erasing = nil
        NW_Doc.touch(page.item, page.player, true)
    end
    if page.grab then
        -- La misura scelta ridimensionando diventa quella di partenza per i
        -- prossimi, finche' non se ne ridimensiona un altro (NW_Ink.endResize
        -- fa lo stesso sulla mappa).
        local g = page.grab
        if page.tool == "edit" and g.item and g.item.s then
            if g.kind == "sym" then
                NW.setLastSize("page", "sym", g.item.s * page:k() / NW.SYMBOL_SIZE)
            elseif g.kind == "note" then
                NW.setLastSize("page", "note", g.item.s)
            end
        end
        page.grab = nil
        NW_Doc.touch(page.item, page.player, true)
    end
end

-- ---------------------------------------------------------------------------
-- Quello che sta sopra a tutto
-- ---------------------------------------------------------------------------

--- Il riquadro di selezione, uguale a quello della mappa: cornice piu' quattro
--- angoli, cosi' legge come una maniglia e non come un rettangolo capitato li'.
local function drawBox(page, n, it, kind, r, g, b, alpha)
    local ax0, ay0, ax1, ay1 = bounds(page, it, kind)
    local x0, y0 = page:toUI(n, ax0, ay0)
    local x1, y1 = page:toUI(n, ax1, ay1)
    x0, y0, x1, y1 = x0 - 3, y0 - 3, x1 + 3, y1 + 3   -- aria, o tocca le lettere

    page:drawRectBorder(x0, y0, x1 - x0, y1 - y0, 0.9 * alpha, r, g, b)
    local t = math.max(4, math.min(x1 - x0, y1 - y0) * 0.28)
    page:drawRect(x0, y0, t, 2, alpha, r, g, b)
    page:drawRect(x0, y0, 2, t, alpha, r, g, b)
    page:drawRect(x1 - t, y0, t, 2, alpha, r, g, b)
    page:drawRect(x1 - 2, y0, 2, t, alpha, r, g, b)
    page:drawRect(x0, y1 - 2, t, 2, alpha, r, g, b)
    page:drawRect(x0, y1 - t, 2, t, alpha, r, g, b)
    page:drawRect(x1 - t, y1 - 2, t, 2, alpha, r, g, b)
    page:drawRect(x1 - 2, y1 - t, 2, t, alpha, r, g, b)
end

--- La riga di testo sotto il cursore, incorniciata: la gomma deve far vedere
--- che cosa sta per portare via prima di portarlo via.
local function drawLineBox(page, n, row, r, g, b, alpha)
    local lines = page:layoutOf(n)
    local line = lines and lines[row]
    if not line then return end
    local px, py, width = page:textRect(n)
    local w = math.min(getTextManager():MeasureStringX(page.font, line.text), width)
    page:drawRectBorder(px - 3, py + (row - 1) * page.lineH - 2,
        w + 6, page.lineH + 4, alpha, r, g, b)
end

function I.overlay(page)
    if not I.owns(page) then return end
    local mx, my = page:getMouseX(), page:getMouseY()
    if mx < 0 or my < 0 or mx > page.width or my > page.height then return end

    local k = page:k()
    local n, ax, ay = page:areaAt(mx, my)

    -- Rosso per la gomma: e' l'unico gesto che distrugge, e sulla mappa e' gia'
    -- cosi'.
    local c = NW_Style.accent
    if page.tool == "erase" then c = NW_Style.close end

    if page.tool == "symbol" then
        if page.symbol and n then
            local tex = NW.symbolTexture(page.symbol.id)
            if tex then
                -- Alla misura e all'angolo con cui nascera' (NW_Placing): prima
                -- era sempre la misura di partenza e dritto, qualunque cosa si
                -- fosse scelto - il simbolo si posava diverso da come lo si vedeva.
                local P = rawget(_G, "NW_Placing")
                local adjust = P and P.enabled()
                if adjust then P.notePageSymbol(page) end
                local size = NW.SYMBOL_SIZE * NW.lastSize("page", "sym")
                local angle = adjust and (P.pageAngle or 0) or 0
                local col = ink(page)
                if angle == 0 then
                    page:drawTextureScaled(tex, mx - size / 2, my - size / 2, size, size,
                        0.45, col.r, col.g, col.b)
                else
                    -- Coordinate assolute, come in NW_Page:paintSymbol.
                    local ox, oy = page:getAbsoluteX() + mx, page:getAbsoluteY() + my
                    local rad = math.rad(angle)
                    local co, si = math.cos(rad), math.sin(rad)
                    local h = size / 2
                    local function corner(dx, dy) return ox + dx * co - dy * si, oy + dx * si + dy * co end
                    local tlx, tly = corner(-h, -h)
                    local trx, try = corner(h, -h)
                    local brx, bry = corner(h, h)
                    local blx, bly = corner(-h, h)
                    page:drawTextureAllPoint(tex, tlx, tly, trx, try, brx, bry, blx, bly,
                        col.r, col.g, col.b, 0.45)
                end
                if adjust then
                    local text = P.status(NW.lastSize("page", "sym"), angle)
                    local ty = my + size / 2 + 4
                    page:drawText(text, mx - size / 2 + 1, ty + 1, 0, 0, 0, 0.5, UIFont.Small)
                    page:drawText(text, mx - size / 2, ty, 1, 1, 1, 0.9, UIFont.Small)
                end
            end
        end
        return
    end

    if page.tool == "erase" then
        page:drawRectBorder(mx - ERASE_PX, my - ERASE_PX, ERASE_PX * 2, ERASE_PX * 2,
            n and 0.75 or 0.25, c.r, c.g, c.b)
    end

    if not TARGETING[page.tool or ""] then return end

    -- Quello in mano, pieno; quello sotto il cursore, velato.
    local g = page.grab
    if g then
        drawBox(page, g.n, g.item, g.kind, c.r, c.g, c.b, 1.0)
        return
    end
    if not n then return end
    local pageIdx = page:pageOf(n)
    if not pageIdx then return end

    local hit = pick(page, n, pageIdx, ax, ay, GRAB_PX / k)
    if hit then
        drawBox(page, n, hit.item, hit.kind, c.r, c.g, c.b, 0.55)
    elseif page.tool == "erase" then
        local row = page:lineAt(n, ax, ay)
        if row then drawLineBox(page, n, row, c.r, c.g, c.b, 0.55) end
    end
end

return NW_PageInk
