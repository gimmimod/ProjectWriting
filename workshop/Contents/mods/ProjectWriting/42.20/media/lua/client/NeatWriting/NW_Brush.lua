--[[ ============================================================================
    NW_Brush - the drawing engine, promoted from the Phase 0 bench.

    A stroke is a polyline, not a cloud of points. DrawOnMap spends one map
    symbol per point and caps out at 250 000 of them; this captures adaptively,
    thins with Ramer-Douglas-Peucker, smooths with Chaikin at draw time and
    paints with drawLine - one quad per segment.

    Measured on the bench: 2366 captured points came out as 566 kept, a 76% cut,
    with the stroke reading the same.
============================================================================ ]]--

if isServer() then return end

-- Per NW.inkById: un tratto riletto porta l'id dell'inchiostro, non il colore.
require "NeatWriting/NW_Config"
require "NeatWriting/NW_DarkMap"

NW_Brush = NW_Brush or {}

local MIN_DIST    = 4.0    -- never record a point closer than this
local ANGLE_COS   = 0.985  -- ...unless the direction turned by about 10 degrees
local RDP_FACTOR  = 0.55   -- epsilon = width * this
local SMOOTH_PASS = 2      -- Chaikin iterations
local W_MIN       = 0.45
local W_MAX       = 1.55
local SPEED_REF   = 26.0   -- units per step considered "fast"

local function dist(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end

local function perpDist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    if len2 == 0 then return dist(px, py, ax, ay) end
    local t = ((px - ax) * dx + (py - ay) * dy) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return dist(px, py, ax + t * dx, ay + t * dy)
end

--- Iterative RDP over a flat {x,y,x,y,...} array. Iterative on purpose: a
--- recursive local would need a forward declaration and can nest deep.
local function simplify(pts, eps)
    local n = #pts / 2
    if n < 3 then return pts end
    local keep = {}
    for i = 1, n do keep[i] = false end
    keep[1], keep[n] = true, true

    local stack = { { 1, n } }
    while #stack > 0 do
        local seg = table.remove(stack)
        local first, last = seg[1], seg[2]
        local maxD, idx = -1, -1
        local ax, ay = pts[first * 2 - 1], pts[first * 2]
        local bx, by = pts[last * 2 - 1], pts[last * 2]
        for i = first + 1, last - 1 do
            local d = perpDist(pts[i * 2 - 1], pts[i * 2], ax, ay, bx, by)
            if d > maxD then maxD, idx = d, i end
        end
        if maxD > eps and idx > 0 then
            keep[idx] = true
            table.insert(stack, { first, idx })
            table.insert(stack, { idx, last })
        end
    end

    local out = {}
    for i = 1, n do
        if keep[i] then
            out[#out + 1] = pts[i * 2 - 1]
            out[#out + 1] = pts[i * 2]
        end
    end
    return out
end

--- Chaikin corner cutting. Endpoints stay put so the stroke keeps its extremes.
local function smooth(pts, passes)
    local cur = pts
    for _ = 1, passes do
        local n = #cur / 2
        if n < 3 then return cur end
        local out = { cur[1], cur[2] }
        for i = 1, n - 1 do
            local ax, ay = cur[i * 2 - 1], cur[i * 2]
            local bx, by = cur[i * 2 + 1], cur[i * 2 + 2]
            out[#out + 1] = ax * 0.75 + bx * 0.25
            out[#out + 1] = ay * 0.75 + by * 0.25
            out[#out + 1] = ax * 0.25 + bx * 0.75
            out[#out + 1] = ay * 0.25 + by * 0.75
        end
        out[#out + 1] = cur[n * 2 - 1]
        out[#out + 1] = cur[n * 2]
        cur = out
    end
    return cur
end

NW_Brush.simplify = simplify
NW_Brush.smooth = smooth

function NW_Brush.newStroke(width, r, g, b)
    return { w = width or 3.0, r = r, g = g, b = b, pts = {}, live = true }
end

--- Adaptive capture: distance OR direction change opens a new point, so tight
--- curves get detail and straight runs cost almost nothing.
function NW_Brush.addPoint(stroke, x, y)
    local pts = stroke.pts
    local n = #pts / 2
    if n == 0 then
        pts[1], pts[2] = x, y
        return true
    end

    local lx, ly = pts[n * 2 - 1], pts[n * 2]
    local d = dist(lx, ly, x, y)
    if d < 0.5 then return false end

    local take = d >= MIN_DIST
    if not take and n >= 2 then
        local px, py = pts[n * 2 - 3], pts[n * 2 - 2]
        local d1 = dist(px, py, lx, ly)
        if d1 > 0 then
            local c = ((lx - px) * (x - lx) + (ly - py) * (y - ly)) / (d1 * d)
            if c < ANGLE_COS then take = true end
        end
    end
    if not take then return false end

    pts[#pts + 1] = x
    pts[#pts + 1] = y
    return true
end

--- Chiude un tratto e lo semplifica.
---
--- `eps` e' quanto un punto puo' scostarsi dalla linea prima di contare
--- davvero, **nelle unita' dei punti**, e chi chiude il tratto e' l'unico che
--- sa quali siano. Sulla pagina i punti stanno in unita' dell'immagine e lo
--- spessore ci e' gia' stato convertito (`page.brush / k`), quindi il calcolo
--- di casa va bene. Sulla mappa no: li' i punti sono quadrati di mondo e lo
--- spessore e' in pixel di schermo, e le due misure non hanno niente a che
--- vedere fra loro. Il conto veniva fatto lo stesso, mescolandole: molto
--- ingranditi si tenevano punti inutili, molto rimpiccioliti si buttava via la
--- forma del tratto. NW_Ink adesso converte i pixel in mondo prima di
--- chiamare, come gia' fa per il raggio della gomma.
function NW_Brush.endStroke(stroke, eps)
    stroke.live = false
    local before = #stroke.pts / 2
    stroke.pts = simplify(stroke.pts, eps or (stroke.w * RDP_FACTOR))
    return before, #stroke.pts / 2
end

--- Il fattore con cui si ricava l'epsilon dallo spessore, per chi deve
--- calcolarselo nelle proprie unita'.
NW_Brush.RDP_FACTOR = RDP_FACTOR

--- Draws a stroke as a smoothed polyline. toUIX/toUIY convert stored
--- coordinates to screen ones, so the same stroke works on a map that pans.
--- I punti e il colore di un tratto, comunque sia arrivato.
---
--- Un tratto vivo porta i punti in `pts` e il colore sciolto in `r, g, b`; uno
--- riletto dal deposito porta `p` e l'id dell'inchiostro in `c`. Sono due forme
--- della stessa cosa, e la conversione sta qui: rimasta fuori, il tratto
--- riletto arrivava a drawLine con tre nil al posto del colore, e drawLine con
--- un nil dentro non e' un disegno mancato - e' un'eccezione Java a ogni
--- fotogramma. (lezione 50)
local function shapeOf(stroke, ui)
    local pts = stroke.pts or stroke.p
    if not pts then return nil end
    local r, g, b = stroke.r, stroke.g, stroke.b
    if not (r and g and b) then
        local ink = NW and NW.inkById and NW.inkById(stroke.c or "black")
        if ink then r, g, b = ink.r, ink.g, ink.b end
    end
    if not (r and g and b) then r, g, b = 0.1, 0.1, 0.1 end
    -- Di notte i segni scuri si alzano. Qui e non alla nascita del tratto: il
    -- colore va schiarito mentre esce, altrimenti si schiariscono solo i tratti
    -- che il colore lo ricavano ogni volta dal nome dell inchiostro.
    r, g, b = NW_DarkMap.lift(r, g, b, ui)
    return pts, r, g, b
end

--- Quanti pixel vale un punto di spessore adesso: lo decide la vista, e vale
--- per TUTTI i tratti allo stesso modo.
---
--- IL PRIMO TENTATIVO LO FACEVA DECIDERE AL TRATTO. Ognuno si teneva
--- l'ingrandimento a cui era nato, e ne usciva un disegno con dentro pennelli
--- diversi: un cerchio fatto guardando da lontano diventava un pennarello
--- enorme avvicinandosi, e uno fatto da vicino spariva allontanandosi. Ogni
--- singolo tratto era fedele a se stesso, e l'insieme non stava in piedi.
---
--- Adesso la penna e' una sola. Lo spessore e' una misura del MONDO uguale per
--- tutti - larga quanto il numero di penna a `ZOOM_REF` - e ogni tratto cresce
--- e cala insieme alla mappa e insieme agli altri, come i simboli di vanilla,
--- che si disegnano a `ISMap.SCALE * getWorldScale()`.
---
--- `ZOOM_REF` e' lo zoom a cui la mappa del mondo si apre quando non ha una
--- vista salvata (18: lo mette ISWorldMap.ShowWorldMap), ed e' anche quello a
--- cui si disegna. Li' la penna 3 e' larga 3 pixel, com'e' sempre stata.
NW_Brush.ZOOM_REF = 18.0

--- E SEGUE LA MAPPA A META', non per intero. Un livello di zoom vale il doppio
--- - e' una piramide di tessere - e la mappa si usa fra il 13 e mezzo di una
--- vista d'insieme e il 18 abbondante di quando ci si scrive sopra: quattro
--- livelli e mezzo, cioe' VENTITRE VOLTE. Seguendo l'ingrandimento per intero,
--- lo stesso tratto e' un capello da lontano e una macchia da vicino - misurato
--- nel log: penna 3 = 1 pixel alla vista d'insieme.
---
--- Mezzo esponente tiene le due cose che servono: i tratti scalano tutti
--- insieme e insieme alla mappa - allargando la vista si assottigliano e non si
--- accavallano piu' - ma fra un capo e l'altro passano da 1 a 8 pixel invece
--- che da 1 a 70. E' un compromesso, ed e' scritto qui perche' si veda che e'
--- una scelta e non una dimenticanza.
local SOFT = 0.5

--- Il moltiplicatore per questo fotogramma. Chiamato una volta per mappa, non
--- una per tratto.
function NW_Brush.penScale(zoom, zoomRef)
    if not zoom then return 1.0 end
    local d = (zoom - (zoomRef or NW_Brush.ZOOM_REF)) * SOFT
    -- Fermato ai due capi: sotto il pixel una linea non e' sottile, e' sparita.
    if d > 4.5 then d = 4.5 elseif d < -6 then d = -6 end
    return 2 ^ d
end

function NW_Brush.render(ui, stroke, toUIX, toUIY, pen)
    local raw, r, g, b = shapeOf(stroke, ui)
    if not raw then return 0 end
    -- Fermato ai due capi: sotto il pixel una linea non e' sottile, e' sparita,
    -- e oltre i quaranta non e' piu' un tratto, e' una macchia che copre quello
    -- che c'e' sotto - a quel punto chi guarda ha ingrandito per vedere la
    -- mappa, non l'inchiostro.
    local width = math.min(40, math.max(1.0, (stroke.w or 3.0) * (pen or 1.0)))
    -- Il lisciato di un tratto finito si calcola UNA VOLTA e si tiene: i punti
    -- non cambiano piu', e rifarlo a ogni fotogramma per ogni tratto della
    -- mappa e' lavoro buttato. Il campo non finisce nel deposito, che scrive
    -- solo w, c e p.
    local pts
    if stroke.live then
        pts = raw
    else
        if not stroke.nwSmooth then stroke.nwSmooth = smooth(raw, SMOOTH_PASS) end
        pts = stroke.nwSmooth
    end
    local n = #pts / 2
    if n < 2 then return 0 end
    local segs = 0
    for i = 1, n - 1 do
        local x1 = toUIX(pts[i * 2 - 1], pts[i * 2])
        local y1 = toUIY(pts[i * 2 - 1], pts[i * 2])
        local x2 = toUIX(pts[i * 2 + 1], pts[i * 2 + 2])
        local y2 = toUIY(pts[i * 2 + 1], pts[i * 2 + 2])
        ui:drawLine(nil, x1, y1, x2, y2, width, 1.0, r, g, b)
        segs = segs + 1
    end
    return segs
end

--- Distance from a point to a stroke, for the eraser.
function NW_Brush.hits(stroke, x, y, radius)
    local pts = stroke.pts or stroke.p
    if not pts then return false end
    local n = #pts / 2
    if n == 0 then return false end
    if n == 1 then return dist(pts[1], pts[2], x, y) <= radius end
    for i = 1, n - 1 do
        if perpDist(x, y, pts[i * 2 - 1], pts[i * 2],
                pts[i * 2 + 1], pts[i * 2 + 2]) <= radius then
            return true
        end
    end
    return false
end
