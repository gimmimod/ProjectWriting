--[[ ============================================================================
    NW_VanillaSymbols - i nostri simboli dentro il pannello del gioco.

    Serve solo con "Lascia la mappa al gioco" acceso, e serve perche' quella
    opzione da sola non bastava: la mod continua a registrare 141 simboli in
    piu' - e' l'unica cosa che deve restare - ma il pannello di vanilla e'
    fatto per i suoi.

    DUE GUASTI, tutti e due visti in una segnalazione con la fotografia.

    1. LA GRIGLIA SFORAVA. Il riquadro delle schede e' alto otto righe fisse
       (BUTTON_HGT*8 + ...) e le schede dentro non scorrono: i simboli oltre
       l'ottava riga venivano disegnati lo stesso, fuori dal riquadro, sopra i
       tasti "Add Note", "Move Marking" e compagnia. Non e' un difetto nostro
       in senso stretto - succede a chiunque installi un pacchetto di simboli -
       ma i simboli in piu' ce li mettiamo noi, quindi e' roba nostra.

       La cura e' quella di vanilla per i pannelli lunghi: setScrollChildren
       piu' addScrollBars sulla scheda, e la barra compare da se' solo quando
       c'e' davvero altro sotto (ISScrollBar:render non disegna niente se il
       contenuto ci sta).

       MA SCORRERE NON E' RITAGLIARE, e le due cose vanno chieste separate:
       setScrollChildren sposta i figli e basta. Con quello solo i simboli
       scorrevano e continuavano a disegnarsi oltre il bordo - lo stesso
       guasto di prima, portato in giro con la barra. Il ritaglio e' lo
       stencil, aperto nel prerender e chiuso nel render (vedi `clip`).

    2. I PACCHETTI NON CONTAVANO NIENTE. Le tre caselle di Opzioni > Mod
       filtravano solo la nostra tavola; il pannello di vanilla legge
       MapSymbolDefinitions e prende tutto quello che trova. Adesso la sua
       lista passa dallo stesso filtro.

       SOLO con la mappa lasciata al gioco. Quando la mappa e' vestita da noi
       il pannello di vanilla resta nascosto ma vivo, e lo usiamo come catalogo
       per posare i simboli (NW_Map.applySymbol lo cerca per id dentro la sua
       buttonList): filtrarlo li' vorrebbe dire che un simbolo scelto dalla
       nostra tavola non si trova piu' e non si posa.
============================================================================ ]]--

if isServer() then return end

require "ISUI/Maps/ISWorldMapSymbols"
require "NeatWriting/NW_Config"

-- Quanto si tiene la barra di scorrimento. Diciassette pixel li prende lei
-- (ISScrollBar si mette a `parent.width - 16` ed e' larga 17), uno di margine.
-- Il riquadro delle schede riempie la larghezza del pannello quasi per intero
-- - resta un margine di pochi pixel - quindi senza allargarlo la barra
-- finirebbe sopra l'ultima colonna di simboli.
local SCROLLBAR_W = 18

-- ---------------------------------------------------------------------------
-- La lista dei simboli
-- ---------------------------------------------------------------------------

ISWorldMapSymbols.populateSymbolList_prepatch_neatwriting = ISWorldMapSymbols.populateSymbolList
function ISWorldMapSymbols:populateSymbolList()
    self:populateSymbolList_prepatch_neatwriting()
    if not NW.vanillaMap() then return end

    local defs = MapSymbolDefinitions.getInstance()
    local kept = {}
    for _, id in ipairs(self.symbolList) do
        local sym = defs:getSymbolById(id)
        local path = sym and sym:getTexturePath() or nil
        -- packEnabled dice si' a tutto quello che non e' di un nostro
        -- pacchetto: i simboli del gioco e quelli di altre mod restano dove
        -- sono, qualunque casella sia spenta.
        if NW.packEnabled(id, path) then kept[#kept + 1] = id end
    end
    self.symbolList = kept
end

-- ---------------------------------------------------------------------------
-- Il posto per la barra
-- ---------------------------------------------------------------------------

ISWorldMapSymbols.RequiredWidth_prepatch_neatwriting = ISWorldMapSymbols.RequiredWidth
function ISWorldMapSymbols.RequiredWidth()
    local w = ISWorldMapSymbols.RequiredWidth_prepatch_neatwriting()
    if NW.vanillaMap() then w = w + SCROLLBAR_W end
    return w
end

-- ---------------------------------------------------------------------------
-- Le schede scorrono
-- ---------------------------------------------------------------------------

--- Dove finisce il contenuto di una scheda.
---
--- Si misura sui tasti veri, non ricalcolando la griglia: quel conto lo ha gia'
--- fatto vanilla poche righe prima, e rifarlo qui vorrebbe dire tenere due
--- copie della stessa formula. `self.buttonList` porta ogni tasto con la sua
--- scheda addosso (`b.tab`), che e' l'id della vista.
local function contentBottom(self, tabId)
    local bottom, pad = 0, 0
    for _, b in ipairs(self.buttonList or {}) do
        if b.tab == tabId then
            bottom = math.max(bottom, b:getY() + b:getHeight())
            if pad == 0 then pad = b:getY() end
        end
    end
    if bottom == 0 then return 0 end
    return bottom + pad
end

--- La rotella scorre la scheda. Senza, l'unico modo di arrivare in fondo
--- sarebbe trascinare la barra, e nessuno lo prova su una griglia di icone.
local function onWheel(view, del)
    view:setYScroll(view:getYScroll() - del * 40)
    return true
end

--- Il ritaglio al bordo della scheda.
---
--- setScrollChildren SPOSTA i figli, non li taglia: i simboli scorrevano ma
--- continuavano a disegnarsi fuori dal riquadro, sopra i tasti sotto - lo
--- stesso guasto di prima, solo che adesso lo si portava in giro con la barra.
---
--- Il ritaglio in Project Zomboid si mette cosi': lo stencil si apre nel
--- prerender e si chiude nel render, e i figli si disegnano in mezzo ai due.
--- E' la ricetta di ISSectionedPanel, che fa esattamente questo per lo stesso
--- motivo. La barra sta dentro il rettangolo, quindi resta visibile.
local function clip(view)
    local basePre, baseRender = view.prerender, view.render
    view.prerender = function(self)
        if basePre then basePre(self) end
        self:setStencilRect(0, 0, self.width, self.height)
    end
    view.render = function(self)
        self:clearStencilRect()
        if baseRender then baseRender(self) end
    end
end

ISWorldMapSymbols.createChildren_prepatch_neatwriting = ISWorldMapSymbols.createChildren
function ISWorldMapSymbols:createChildren()
    self:createChildren_prepatch_neatwriting()
    if not NW.vanillaMap() then return end
    if not (self.panel and self.panel.viewList) then return end

    for _, entry in ipairs(self.panel.viewList) do
        local view = entry.view
        local height = view and contentBottom(self, view.ID) or 0
        if height > 0 then
            view:setScrollChildren(true)
            view:addScrollBars()
            view:setScrollHeight(height)
            view.onMouseWheel = onWheel
            clip(view)
        end
    end
end
