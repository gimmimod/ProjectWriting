--[[ ============================================================================
    NW_Page - la pagina: una tela ferma, e niente di piu'.

    PERCHE' NON E' UNA UIWorldMap. Lo era, e in fase 0 aveva senso: il motore
    della mappa e' l'unica cosa in Project Zomboid che sappia tenere del testo
    ancorato a coordinate proprie mentre la vista si sposta e si ingrandisce.
    Solo che questa vista non si sposta e non si ingrandisce - un foglio sta
    fermo - quindi di tutto quel motore restava in uso una moltiplicazione per
    una costante, mentre il suo renderer continuava a disegnare ai bordi della
    pagina roba che nessuna API permette di spegnere. (Lezione 30.)
    Di quel motore resta solo NW_TextLayer, per girare i biglietti.

    COORDINATE. Tutto quello che si scrive e' in unita' pagina RELATIVE ALLA
    FACCIATA: 0,0 e' l'angolo alto-sinistro dell'area di carta, non
    dell'immagine. Cosi' un tratto non dipende dalla risoluzione dello schermo,
    ne' da quale meta' del quaderno gli e' capitata.

    LA SCRITTURA LA FA IL RIQUADRO DI VANILLA, E BASTA. C'e' stato un tentativo
    di tenerlo fuori dallo schermo come semplice tastiera e di impaginare il
    testo per conto nostro: dava l'a capo dove volevamo e le righe dove
    volevamo, ma il cursore era di un altro - e il cursore di UITextBox2 e'
    **(riga, colonna)**, non un indice assoluto. Ce lo dice \`setCursorLine\`, che
    esiste accanto a \`setCursorPos\` ed e' quello che vanilla usa per rimettere
    il cursore in cima quando cambia pagina.

    Leggere quel numero come se fosse un indice assoluto e' il motivo per cui il
    cursore saltava sulla prima riga dopo ogni Invio e si spostava a caso: dopo
    un a capo la colonna torna a zero, e zero letto come indice assoluto e'
    l'inizio del testo.

    Quindi il riquadro torna al suo posto, VISIBILE e sopra alla carta, e si
    prende quello che sa gia' fare: cursore, selezione col trascinamento,
    cancellazione, Invio, tastiere non latine. Noi disegnamo il testo solo
    quando il riquadro non c'e' - con la gomma in mano, o su una facciata che si
    sta guardando - perche' li' serve vederlo senza poterlo toccare.

    ORDINE DI DISEGNO. Il motore chiama prerender, poi i figli, poi render.
      prerender  la carta, il testo in sola lettura, l'inchiostro, i simboli
      figli      i riquadri di scrittura e i biglietti girati
      render     quello che sta sopra a tutto: gomma, anteprima, selezione
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Doc"
require "NeatWriting/NW_Layouts"
require "NeatWriting/NW_Sound"
require "NeatWriting/NW_Style"
require "NeatWriting/UI/NW_TextLayer"
require "NeatWriting/UI/NW_Writer"

--- Il tetto di battute per riga. Novanta e' dove arrivano gia' oggi la carta a
--- quadretti e la scheda su uno schermo 1080p: e' il massimo che si e' guardato
--- e giudicato accettabile, non un numero scelto a tavolino.
local MAX_CHARS = 90

NW_Page = ISPanel:derive("NW_Page")

-- ---------------------------------------------------------------------------
-- Geometria
-- ---------------------------------------------------------------------------

--- Da unita' immagine a pixel.
function NW_Page:k()
    return self.width / self.media.width
end

--- Quale facciata sta sotto un punto in pixel, e dove dentro quell'area.
--- Torna nil sulla rilegatura, sugli anelli e fuori dalla carta.
function NW_Page:areaAt(ux, uy)
    local k = self:k()
    local n = NW_Layouts.areaAt(self.media, ux / k, uy / k)
    if not n then return nil end
    local x0, y0 = NW_Layouts.area(self.media, n)
    return n, ux / k - x0, uy / k - y0
end

--- Coordinate di facciata -> pixel dell'elemento.
function NW_Page:toUI(n, ax, ay)
    local x0, y0 = NW_Layouts.area(self.media, n)
    local k = self:k()
    return (x0 + ax) * k, (y0 + ay) * k
end

--- Tiene un punto dentro la sua facciata.
function NW_Page:clamp(n, ax, ay)
    local x0, y0, x1, y1 = NW_Layouts.area(self.media, n)
    return math.max(0, math.min(x1 - x0, ax)), math.max(0, math.min(y1 - y0, ay))
end

--- La pagina mostrata nella facciata `n`, o nil se l'oggetto non ne ha
--- abbastanza: un supporto con un numero dispari di pagine lascia l'ultima
--- spalla vuota, e su una spalla vuota non si scrive.
function NW_Page:pageOf(n)
    local p = NW_Layouts.pageOf(self.media, self.spread, n)
    if p > self.pageCount then return nil end
    return p
end

--- Il riquadro di scrittura di una facciata, in pixel: x, y del PRIMO RIGO
--- (il suo bordo alto), larghezza, altezza e quante righe ci stanno.
---
--- Le righe sono alte quanto la grafia, perche' e' il riquadro di vanilla a
--- disegnarle e la sua spaziatura non si cambia. Dove la carta ha righe
--- stampate il riquadro parte comunque dalla prima, cosi' almeno l'attacco
--- della scrittura cade dove deve.
function NW_Page:textRect(n)
    local k = self:k()
    local x0, y0, x1, y1 = NW_Layouts.textBox(self.media, n)
    local _, fh = NW_Writer.font()

    local minTop = y0 * k
    local top = minTop
    local t = self.media.text or {}
    if t.ruled then top = NW_Layouts.firstLine(self.media, n) * k - fh end

    if top < minTop then
        -- La prima riga stampata cade sopra il margine: non la si schiaccia sul
        -- margine, si scende di una riga INTERA e si comincia dalla seconda.
        --
        -- Schiacciarla buttava via l'aggancio proprio dove serviva: la pagina
        -- era gia' scesa alla scala a cui le righe di scrittura misurano una
        -- riga stampata, e poi lo spostamento di due pixel le disallineava
        -- tutte. Un passo di scrittura vale un numero intero di righe stampate,
        -- quindi saltarne uno resta agganciato.
        --
        -- Dove l'aggancio non c'e' - la scala non e' scesa perche' costava
        -- troppo - non c'e' niente da salvare e si schiaccia come prima: saltare
        -- una riga costerebbe una riga di scrittura per niente.
        local printed = NW_Layouts.line(self.media) * k
        local ratio = printed > 0 and fh / printed or 0
        local snapped = ratio > 0 and math.abs(ratio - math.floor(ratio + 0.5)) < 0.02
        if snapped then
            top = top + math.ceil((minTop - top) / fh) * fh
        else
            top = minTop
        end
    end

    local h = y1 * k - top
    local x = x0 * k
    local w = (x1 - x0) * k

    -- LA RIGA NON PUO' CRESCERE ALL'INFINITO. I margini sono in unita' pagina e
    -- si allargano con la pagina, ma la grafia e' fissa a quaranta pixel: piu'
    -- grande e' lo schermo, piu' battute entrano nella stessa riga. La carta a
    -- quadretti arrivava a centoquattordici battute su un 1440p, e una riga
    -- lunga il doppio del leggibile e' scritta male comunque sia larga il
    -- foglio. Oltre il tetto si stringe e si centra: la pagina resta piena in
    -- altezza, che e' quello che conta, e in larghezza guadagna un margine che
    -- somiglia a quello di un libro.
    local maxW = NW_Writer.advance() * MAX_CHARS
    if w > maxW then
        x = x + (w - maxW) / 2
        w = maxW
    end

    return x, top, w, h, math.max(1, math.floor(h / fh))
end

-- ---------------------------------------------------------------------------
-- Costruzione
-- ---------------------------------------------------------------------------

function NW_Page:createChildren()
    self.font, self.lineH = NW_Writer.font()
    self.lines = {}

    -- Un riquadro di scrittura per facciata, creato UNA VOLTA E ALLA SUA
    -- MISURA DEFINITIVA. Nascerne uno piccolo e allargarlo dopo era il difetto
    -- della primissima versione: la larghezza dell'a capo la decide il riquadro
    -- quando nasce, e un riquadro nato largo dieci pixel non manda a capo mai.
    self.boxes = {}
    for n = 1, NW_Layouts.areaCount(self.media) do
        local x, y, w, h, rows = self:textRect(n)
        local box = NW_Writer.newBox(x, y, w, h, rows,
            function(text) self:onTyped(n, text) end)
        self:addChild(box)
        self.boxes[n] = box
    end

    -- Il disegnatore di testo ruotato, grande quanto la pagina e sordo al
    -- mouse. Dentro c'e' un oggetto della mappa, che e' l'unico che sappia
    -- girare del testo; se non nascesse, i biglietti tornano dritti e la pagina
    -- resta intera.
    local ok, layer = pcall(function()
        local l = NW_TextLayer:new(0, 0, self.width, self.height)
        l:initialise()
        l:instantiate()
        return l
    end)
    if ok and layer then
        self.textLayer = layer
        self:addChild(layer)
    else
        print("NW_Page: livello di testo non disponibile, biglietti dritti")
    end

    self:refresh()
end

--- Rimette a posto il testo e chi puo' toccarlo. Da chiamare quando cambia
--- l'apertura, lo strumento o l'inchiostro - non a ogni frame.
function NW_Page:refresh()
    -- Senza un inchiostro non si scrive nemmeno a macchina: il pannello lo toglie
    -- quando la penna esce dalla borsa (NW_Panel:selectTool), e un campo di testo
    -- che resta aperto scriverebbe con una penna che non c'e' piu'.
    local writing = self.tool == "text" and self.editable and self.inkId ~= nil

    local limit = NW.pageCharLimit()
    for n, box in ipairs(self.boxes) do
        local page = self:pageOf(n)
        local text = page and NW_Doc.text(self.item, page) or ""
        if box:getInternalText() ~= text then box:setText(text) end
        self.lines[n] = nil

        -- Il tetto di battute, mai sotto quello che la facciata contiene gia':
        -- un tetto abbassato dopo non deve poter accorciare una pagina scritta
        -- prima. Si scrive solo cancellando, finche' non si torna sotto.
        if limit > 0 then
            box:setMaxTextLength(math.max(limit, #text))
        else
            box:setMaxTextLength(6000)
        end

        if page and writing then
            NW_Writer.setInk(box, self.ink or NW.INKS[1])
            box:setVisible(true)
        else
            if box:isFocused() then box:unfocus() end
            box:setVisible(false)
        end
    end

    -- Presa la penna il cursore c'e' subito, sulla prima facciata utile: si
    -- comincia a battere senza dover prima trovare il riquadro. Cliccare serve
    -- a spostarlo, non ad accenderlo - e se sta gia' lampeggiando da qualche
    -- parte non glielo si porta via.
    if writing and not self:typing() then
        for _, box in ipairs(self.boxes) do
            if box:getIsVisible() then box:focus() break end
        end
    end
end

--- Ogni battuta finisce subito nell'oggetto: non c'e' un tasto per salvare
--- perche' non c'e' un momento in cui il testo non e' gia' salvato.
---
--- Il testo di una facciata ha un colore solo, ed e' quello che si ha in mano
--- quando la si scrive: cambiare penna e battere un tasto ricolora la pagina.
function NW_Page:onTyped(n, text)
    local page = self:pageOf(n)
    if not page or not self.editable then return end
    self.lines[n] = nil
    NW_Doc.setText(self.item, page, text)
    if text ~= "" then NW_Doc.setTextInk(self.item, page, self.inkId) end
    NW_Doc.touch(self.item, self.player)
end

--- Prima di cambiare apertura o di chiudere.
function NW_Page:commit()
    for n, box in ipairs(self.boxes) do
        local page = self:pageOf(n)
        if page then NW_Doc.setText(self.item, page, box:getInternalText()) end
    end
    NW_Doc.touch(self.item, self.player, true)
end

--- Cambia apertura. Il rumore della pagina sta QUI e non in chi ha chiesto il
--- cambio: la carta fa rumore perche' gira, non perche' e' stato premuto un
--- tasto. Legato al tasto valeva solo per i due tasti a schermo, e sfogliando
--- da tastiera la stessa pagina girava in silenzio.
function NW_Page:setSpread(s)
    local was = self.spread
    self:commit()
    self.spread = math.max(1, math.min(self.spreads, s))
    self:refresh()
    if self.spread ~= was then NW_Sound.flip(self.player) end
end

--- Vero mentre il cursore lampeggia in uno dei riquadri.
function NW_Page:typing()
    for _, box in ipairs(self.boxes or {}) do
        if box:getIsVisible() and box:isFocused() then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Il testo visto da fuori
-- ---------------------------------------------------------------------------
-- Serve quando il riquadro non c'e': per disegnarlo in sola lettura, e per dire
-- alla gomma da dove a dove arriva ogni riga. L'impaginazione e' la stessa che
-- fa il riquadro - stessa grafia, stessa larghezza, stesso a capo goloso -
-- quindi le due immagini si somigliano e passare da una all'altra non salta.

function NW_Page:layoutOf(n)
    if not self.lines[n] then
        local _, _, width = self:textRect(n)
        self.lines[n] = NW_Writer.layout(self.boxes[n]:getInternalText(),
            self.font, width)
    end
    return self.lines[n]
end

--- Su quale riga di testo cade un punto. Serve alla gomma: una riga per volta,
--- non tutta la pagina.
function NW_Page:lineAt(n, ax, ay)
    local lines = self:layoutOf(n)
    if #lines == 0 then return nil end

    local k = self:k()
    local px, py, width = self:textRect(n)
    local x0, y0 = NW_Layouts.area(self.media, n)
    local uy = (y0 + ay) * k

    if uy < py then return nil end
    local row = math.floor((uy - py) / self.lineH) + 1
    if row > #lines or lines[row].text == "" then return nil end

    -- e deve essere davvero sopra a delle lettere, non nel bianco a destra
    local ux = (x0 + ax) * k
    local w = getTextManager():MeasureStringX(self.font, lines[row].text)
    if ux < px - 4 or ux > px + math.min(w, width) + 4 then return nil end
    return row
end

--- Toglie una riga di testo, con il separatore che la lega alla successiva.
function NW_Page:eraseLine(n, row)
    local lines = self:layoutOf(n)
    local line = lines[row]
    if not line then return false end

    local box = self.boxes[n]
    local text = box:getInternalText() or ""
    local stop = line.to
    local after = text:sub(stop + 1, stop + 1)
    if after == "\n" or after == " " then stop = stop + 1 end

    box:setText(text:sub(1, line.from - 1) .. text:sub(stop + 1))
    self:onTyped(n, box:getInternalText())
    return true
end

-- ---------------------------------------------------------------------------
-- Disegno
-- ---------------------------------------------------------------------------

function NW_Page:prerender()
    if self.textLayer then self.textLayer:clear() end

    local tex = NW_Style.tex(self.media.texture)
    if tex then
        self:drawTextureScaled(tex, 0, 0, self.width, self.height, 1, 1, 1, 1)
    else
        self:drawRect(0, 0, self.width, self.height, 1, 0.92, 0.90, 0.85)
    end

    for n = 1, NW_Layouts.areaCount(self.media) do
        local page = self:pageOf(n)
        if page then
            if not self.boxes[n]:getIsVisible() then self:paintText(n, page) end
            self:paintInk(n, page)
            self:paintSymbols(n, page)
            self:paintNotes(n, page)
        end
    end

    if self.live then self:paintStroke(self.live.n, self.live) end
end

--- Il testo quando il riquadro e' via: stessa grafia, stesse righe, stesso
--- posto. L'unica differenza e' che non si puo' toccare.
function NW_Page:paintText(n, page)
    local lines = self:layoutOf(n)
    if #lines == 0 then return end

    local px, py, _, _, rows = self:textRect(n)
    local ink = NW.inkById(NW_Doc.textInk(self.item, page) or self.inkId or "black")

    -- NIENTE SI PERDE IN FONDO. Una facciata scritta su una pagina piu' grande
    -- di questa ha piu' righe di quante qui ne stiano: prima le ultime non si
    -- disegnavano, e chi leggeva non sapeva nemmeno che ci fossero. Adesso la
    -- grafia si stringe quanto serve perche' ci stiano tutte.
    local zoom = (#lines > rows) and (rows / #lines) or 1
    local step = self.lineH * zoom
    for i = 1, #lines do
        local s = lines[i].text
        if s ~= "" then
            if zoom < 1 then
                self:drawTextZoomed(s, px, py + (i - 1) * step, zoom,
                    ink.r, ink.g, ink.b, 1, self.font)
            else
                self:drawText(s, px, py + (i - 1) * step,
                    ink.r, ink.g, ink.b, 1, self.font)
            end
        end
    end
end

function NW_Page:paintInk(n, page)
    local list = NW_Doc.list(self.item, page, "ink", false)
    if not list then return end
    for _, s in ipairs(list) do self:paintStroke(n, s) end
end

--- Un tratto: i punti sono in unita' di facciata, lo spessore anche, cosi' una
--- linea sottile resta sottile su qualunque schermo.
function NW_Page:paintStroke(n, s)
    -- Il tratto vivo porta i punti in `pts` (e' la forma di NW_Brush), quello
    -- salvato in `p`: si disegnano con lo stesso codice.
    local pts = s.p or s.pts
    if not pts or #pts < 4 then return end
    local ink = NW.inkById(s.c or "black")
    local k = self:k()
    local w = math.max(1, (s.w or 3) * k)
    local ax, ay = self:toUI(n, pts[1], pts[2])
    for i = 3, #pts - 1, 2 do
        local bx, by = self:toUI(n, pts[i], pts[i + 1])
        self:drawLine(nil, ax, ay, bx, by, w, 1.0, ink.r, ink.g, ink.b)
        ax, ay = bx, by
    end
end

--- Un simbolo, girato se serve.
---
--- Dritto si disegna con drawTextureScaled, che e' la strada battuta. Girato
--- serve un quadrilatero qualunque, e per quello c'e' drawTextureAllPoint.
function NW_Page:paintSymbol(n, s)
    local tex = NW.symbolTexture(s.id)
    if not tex then return end
    local ink = NW.inkById(s.c or "black")
    local k = self:k()
    local size = (s.s or 40) * k
    local cx, cy = self:toUI(n, s.x, s.y)
    local angle = s.r or 0

    if angle == 0 then
        self:drawTextureScaled(tex, cx - size / 2, cy - size / 2, size, size,
            1, ink.r, ink.g, ink.b)
        return
    end

    -- COORDINATE ASSOLUTE. drawTextureScaled le vuole relative all'elemento,
    -- questa no: passandole relative il simbolo ruotato finiva in cima allo
    -- schermo, cioe' fuori dal foglio - ed e' proprio quello scarto a dire di
    -- che tipo sono, perche' e' esattamente la distanza fra l'angolo della
    -- pagina e l'angolo dello schermo.
    local ox, oy = self:getAbsoluteX(), self:getAbsoluteY()
    local rad = math.rad(angle)
    local co, si = math.cos(rad), math.sin(rad)
    local h = size / 2
    local function corner(dx, dy)
        return ox + cx + dx * co - dy * si, oy + cy + dx * si + dy * co
    end
    local tlx, tly = corner(-h, -h)
    local trx, try = corner(h, -h)
    local brx, bry = corner(h, h)
    local blx, bly = corner(-h, h)
    self:drawTextureAllPoint(tex, tlx, tly, trx, try, brx, bry, blx, bly,
        ink.r, ink.g, ink.b, 1)
end

function NW_Page:paintSymbols(n, page)
    local list = NW_Doc.list(self.item, page, "sym", false)
    if not list then return end
    for _, s in ipairs(list) do self:paintSymbol(n, s) end
end

--- I biglietti, nella grafia della pagina, girati e alla loro misura.
---
--- La strada buona e' NW_TextLayer, che li gira come fa la mappa. Quella di
--- ripiego, se quel motore non risponde, e' drawTextZoomed: dritti, ma almeno
--- la misura la sa cambiare.
function NW_Page:paintNotes(n, page)
    local list = NW_Doc.list(self.item, page, "note", false)
    if not list then return end
    local rotated = self.textLayer and self.textLayer.works ~= false

    for _, note in ipairs(list) do
        local ink = NW.inkById(note.c or "black")
        local ux, uy = self:toUI(n, note.x, note.y)
        local zoom = note.s or 1
        if rotated then
            local w = getTextManager():MeasureStringX(self.font, note.t or "") * zoom
            self.textLayer:add(note.t or "", ux + w / 2, uy + self.lineH * zoom / 2,
                note.r or 0, zoom, ink.r, ink.g, ink.b, 1)
        elseif zoom == 1 then
            self:drawText(note.t or "", ux, uy, ink.r, ink.g, ink.b, 1, self.font)
        else
            self:drawTextZoomed(note.t or "", ux, uy, zoom, ink.r, ink.g, ink.b, 1, self.font)
        end
    end
end

function NW_Page:render()
    if self.onOverlay then self.onOverlay(self) end
    self:paintCounter()
end

--- Quante battute restano, sotto il riquadro in cui si sta scrivendo. Solo con
--- un tetto: senza, un numero che sale e basta non dice niente.
function NW_Page:paintCounter()
    local limit = NW.pageCharLimit()
    if limit <= 0 then return end
    for n, box in ipairs(self.boxes or {}) do
        if box:getIsVisible() and box:isFocused() then
            local used = #(box:getInternalText() or "")
            local x, y, w, h = self:textRect(n)
            local label = tostring(used) .. " / " .. tostring(limit)
            local c = (used >= limit) and NW_Style.accent or NW_Style.dim
            self:drawTextRight(label, x + w, y + h + 2, c.r, c.g, c.b, 0.85, UIFont.Small)
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- Mouse
-- ---------------------------------------------------------------------------
-- Con la penna in mano i riquadri di scrittura coprono la carta e si prendono
-- loro i clic: cursore e selezione sono i loro. Qui arriva solo quello che
-- cade fuori, e tutto il resto degli strumenti.

--- Con Ctrl o Shift e un simbolo o un biglietto in mano la rotella e' di
--- NW_Placing (che la legge dall'evento OnMouseWheel): qui la si tiene, cosi'
--- non passa a chi sta sotto - la visuale del gioco, che zoomerebbe.
function NW_Page:onMouseWheel(del)
    local P = rawget(_G, "NW_Placing")
    return P ~= nil and P.wheelIsOurs()
end

function NW_Page:onMouseDown(x, y)
    if self.onPress then self.onPress(self, x, y) end
    return true
end

function NW_Page:onMouseMove(dx, dy)
    if self.onDrag then self.onDrag(self, self:getMouseX(), self:getMouseY()) end
    return true
end

function NW_Page:onMouseMoveOutside(dx, dy)
    if self.onDrag then self.onDrag(self, self:getMouseX(), self:getMouseY()) end
    return true
end

function NW_Page:onMouseUp(x, y)
    if self.onRelease then self.onRelease(self, x, y) end
    return true
end

function NW_Page:onMouseUpOutside(x, y)
    if self.onRelease then self.onRelease(self, x, y) end
    return true
end

function NW_Page:onRightMouseDown(x, y)
    if self.onRightPress then self.onRightPress(self, x, y) end
    return true
end

-- ---------------------------------------------------------------------------

function NW_Page:new(x, y, width, height, media, item, player, editable)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.moveWithMouse = false
    o.media = media or NW_Layouts.MEDIA.sheet
    o.item = item
    o.player = player
    o.editable = editable ~= false
    o.pageCount = NW_Layouts.pageCount(o.media, item and NW_Doc.vanillaPages(item) or 1)
    o.spreads = NW_Layouts.spreads(o.media, o.pageCount)
    o.spread = 1
    o.tool = nil
    o.inkId = "black"
    o.ink = NW.INKS[1]
    o.brush = NW.BRUSH.DEFAULT
    o.lines = {}
    return o
end

return NW_Page
