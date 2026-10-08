--[[ ============================================================================
    NW_Writer - la scrittura lineare, quella "stile Word".

    SI SCRIVE A MANO. Il carattere e' UIFont.Handwritten e non cambia mai: e' la
    grafia con cui vanilla scrive le note sulla mappa, ed e' l'unica che su un
    foglio di carta sembri scrittura invece che stampa. Sta in
    media/fonts/handwritten.fnt, fuori dalle cartelle 1x/2x: e' alta 40 pixel
    sempre, non segue la scala dell'interfaccia.

    IL RIQUADRO DI VANILLA FA IL SUO MESTIERE. C'e' stato un tentativo di
    tenerlo fuori dallo schermo come semplice tastiera e di impaginare il testo
    per conto nostro. Non regge, e il motivo e' preciso: il cursore di
    UITextBox2 e' **(riga, colonna)**, non un indice assoluto - lo dice
    \`setCursorLine\`, che esiste accanto a \`setCursorPos\`. Letto come indice
    assoluto, dopo ogni Invio vale zero, e zero e' l'inizio del testo: il
    cursore saltava sulla prima riga a ogni a capo.

    Quindi il riquadro sta al suo posto, sopra alla carta, e gli si toglie solo
    il fondo grigio e la cornice squadrata. Cursore, selezione col
    trascinamento, cancellazione, Invio e tastiere non latine sono i suoi.

    NASCE GIA' DELLA SUA MISURA. La larghezza a cui manda a capo la decide
    quando nasce: un riquadro creato a dieci pixel e allargato dopo non manda a
    capo mai, ed e' quello che faceva la primissima versione.

    Quello che resta qui e' l'impaginazione IN SOLA LETTURA - stessa grafia,
    stessa larghezza, stesso a capo goloso - che serve a disegnare il testo
    quando il riquadro non c'e' e a dire alla gomma da dove a dove arriva ogni
    riga.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISTextEntryBox"
require "NeatWriting/NW_Config"

NW_Writer = NW_Writer or {}
local W = NW_Writer

local cached = nil

--- Il carattere della scrittura: la grafia, o il ripiego se una lingua non ce
--- l'ha. Si chiede una volta e si tiene.
function W.font()
    if cached then return cached.font, cached.h end
    local tm = getTextManager()
    for _, name in ipairs({ "Handwritten", "Medium", "Small" }) do
        local font = UIFont[name]
        if font then
            local ok, h = pcall(function() return tm:getFontHeight(font) end)
            if ok and h and h > 0 then
                cached = { font = font, h = h, name = name }
                return font, h
            end
        end
    end
    cached = { font = UIFont.Small, h = 12, name = "Small" }
    return cached.font, cached.h
end

-- ---------------------------------------------------------------------------
-- Impaginazione in sola lettura
-- ---------------------------------------------------------------------------

--- Spezza il testo in righe che stanno in `width` pixel, dicendo anche DA DOVE
--- A DOVE arriva ogni riga nel testo di partenza.
---
--- Gli scarti servono alla gomma: cancellare una riga sola vuol dire sapere
--- quali caratteri sono quella riga.
---
--- Si misura la riga intera che si sta costruendo, non il singolo carattere:
--- MeasureStringX su un carattere solo non e' affidabile, e sommandone i
--- risultati la riga non arrivava mai al bordo.
function W.layout(text, font, width)
    local out = {}
    if not text or text == "" then return out end

    local tm = getTextManager()
    local len = #text
    local from, i = 1, 1
    local lastSpace = nil

    while i <= len do
        local ch = text:sub(i, i)
        if ch == "\n" then
            out[#out + 1] = { text = text:sub(from, i - 1), from = from, to = i - 1 }
            i = i + 1
            from, lastSpace = i, nil
        elseif i > from and tm:MeasureStringX(font, text:sub(from, i)) > width then
            if lastSpace and lastSpace > from then
                out[#out + 1] = { text = text:sub(from, lastSpace - 1), from = from, to = lastSpace - 1 }
                from = lastSpace + 1      -- lo spazio si mangia nell'andare a capo
                i = from
            else
                -- una parola sola piu' larga della riga: si taglia dov'e'
                out[#out + 1] = { text = text:sub(from, i - 1), from = from, to = i - 1 }
                from = i
            end
            lastSpace = nil
        else
            if ch == " " then lastSpace = i end
            i = i + 1
        end
    end
    out[#out + 1] = { text = text:sub(from, len), from = from, to = len }
    return out
end

-- ---------------------------------------------------------------------------
-- Il riquadro
-- ---------------------------------------------------------------------------

--- Un riquadro di scrittura sulla carta: nessun fondo, nessuna cornice, la
--- grafia della pagina.
---
--- `onChange` viene chiamata a ogni battuta: e' li' che si salva, perche' un
--- salvataggio che aspetta un tasto e' un salvataggio che prima o poi si perde.
--- La larghezza media di una battuta, in pixel.
---
--- Misurata su un campione di lettere vere e non su una sola: nella grafia una
--- "i" e una "m" non si somigliano affatto, e prendere la larghezza di un
--- carattere qualunque sbagliava di quasi il doppio. Il carattere non cambia
--- mai - Handwritten non sta nelle cartelle 1x/2x e non segue la scala
--- dell'interfaccia - quindi si misura una volta.
local advance
function W.advance()
    if advance then return advance end
    local font = W.font()
    local sample = "the quick brown fox jumps over the lazy dog"
    local ok, w = pcall(function() return getTextManager():MeasureStringX(font, sample) end)
    if ok and w and w > 0 then
        advance = w / #sample
    else
        local _, h = W.font()
        advance = h * 0.27
    end
    return advance
end

function W.newBox(x, y, w, h, rows, onChange)
    local font = W.font()
    local box = ISTextEntryBox:new("", x, y, w, h)
    box:initialise()
    box:instantiate()
    box:setFont(font)
    box:setMultipleLine(true)
    box:setMaxLines(math.max(1, rows or 1))
    box:setMaxTextLength(6000)
    box:setEditable(true)

    -- Il fondo grigio e la cornice squadrata sono le uniche parti che stonano
    -- sulla carta. Il testo e il cursore li disegna l'oggetto Java, che non
    -- passa di qui.
    box.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    box.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    box.prerender = function() end

    box.onTextChangeFunction = nil
    box.onTextChange = function(self)
        if onChange then onChange(self:getInternalText()) end
    end
    return box
end

--- Il colore dell'inchiostro nel riquadro.
function W.setInk(box, ink)
    if not box or not ink then return end
    box:setTextRGBA(ink.r, ink.g, ink.b, 1)
end

return NW_Writer
