--[[ ============================================================================
    NW_TextLayer - il pezzo di motore mappa che serve a girare del testo.

    PERCHE' RITORNA UNA UIWorldMap. La pagina non lo e' piu' e non deve
    ridiventarlo (lezione 30). Ma nel gioco esiste una sola funzione che
    disegni del testo RUOTATO E SCALATO,

        UIWorldMap:DrawTextSdfRotated(layerID, testo, x, y,
                                      ancoraX, ancoraY, gradi, scala,
                                      prospettiva, zoom, r, g, b, a)

    e non e' un metodo di un elemento qualunque: sta sull'oggetto Java della
    mappa e vuole l'id di un suo livello di testo. E' con quella che vanilla
    gira le note sulla mappa del mondo, ed e' il motivo per cui li' si possono
    ruotare e qui no.

    Quindi si prende quella e basta: una UIWorldMap **senza mappa dentro** -
    stile azzerato, nessun livello di texture, sfondo e griglia trasparenti,
    nessun dato cartografico caricato - grande quanto la pagina e sorda al
    mouse. Non disegna niente per conto suo: e' una superficie su cui chiamare
    quella funzione. (Lezione 32.)

    LE DUE API NON SONO INTERCAMBIABILI. Sfondo, griglia e stile stanno sulla
    v1; **i livelli di testo esistono solo sulla v3**. Chiedere newTextLayer
    alla v1 non torna nil da qualche parte: fa saltare tutta l'apertura della
    finestra, perche' in questo Lua chiamare un valore nullo e' un errore che
    nemmeno pcall trattiene (lezione 33). Le due righe qui sotto che chiedono
    l'API giusta sono la differenza fra una finestra che si apre e una che no.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "NeatWriting/UI/NW_Writer"

NW_TextLayer = ISPanel:derive("NW_TextLayer")

--- Il nome del nostro livello di testo. Vanilla ne ha uno suo per le note della
--- mappa; questo e' il nostro, con la stessa grafia.
local LAYER = "nw-note"

function NW_TextLayer:instantiate()
    self.javaObject = UIWorldMap.new(self)
    self.javaObject:setX(self.x)
    self.javaObject:setY(self.y)
    self.javaObject:setWidth(self.width)
    self.javaObject:setHeight(self.height)
    self.javaObject:setAnchorLeft(true)
    self.javaObject:setAnchorRight(false)
    self.javaObject:setAnchorTop(true)
    self.javaObject:setAnchorBottom(false)

    -- Sorda al mouse: sta sopra alla pagina e i clic devono arrivare sotto, a
    -- chi disegna. Senza questo il foglio diventerebbe intoccabile.
    self.javaObject:setConsumeMouseEvents(false)

    -- v1 per lo sfondo, v3 per il testo. Sono due viste dello stesso oggetto e
    -- lo stile e' in comune, ma i livelli di testo li sa creare solo la v3.
    self.mapAPI = self.javaObject:getAPIv1()
    self.textAPI = self.javaObject:getAPIv3()

    -- Si spegne tutto quello che il renderer disegnerebbe da solo. Niente
    -- livello di texture, che nella vecchia pagina era quello che portava la
    -- carta: qui la carta la disegna NW_Page e questo oggetto non deve mettere
    -- un pixel suo da nessuna parte.
    --
    -- Ogni riga qui sotto ha un precedente in ISMapDefinitions, e i controlli
    -- sono su quello che potrebbe TORNARE nullo, non attorno alla chiamata: un
    -- pcall attorno a un metodo che non esiste non trattiene niente
    -- (lezione 33), un `if` su un valore nullo si'.
    -- QUI NON SI SVUOTA LO STILE, e la riga tolta merita una spiegazione.
    --
    -- C'era `getStyleAPI():clear()`, per "spegnere tutto quello che il renderer
    -- disegnerebbe da solo". Non serviva: questa mappa non ha dati cartografici
    -- caricati, quindi non c'e' nessun livello da spegnere. E poteva costare
    -- caro: aprendo un foglio e poi la mappa del mondo, sulla mappa del mondo le
    -- zone sconosciute a volte venivano nere invece che color carta - cioe' la
    -- carta sopra la mappa non c'era piu' (MapUtils.overlayPaper). Se lo stile
    -- e' condiviso fra le UIWorldMap invece che appartenere a ognuna, quella
    -- riga lo cancellava per tutte.
    --
    -- Non sappiamo quale delle due sia vera, e non serve saperlo: se e' per
    -- oggetto non cambia niente, se e' condiviso smettiamo di rompere la mappa
    -- del mondo. Lo sfondo e la griglia trasparenti bastano da soli.
    self.mapAPI:setBackgroundRGBA(0, 0, 0, 0)
    self.mapAPI:setUnvisitedRGBA(0, 0, 0, 0)
    self.mapAPI:setUnvisitedGridRGBA(0, 0, 0, 0)

    -- Il livello di testo: e' l'id che DrawTextSdfRotated vuole come primo
    -- argomento. La grafia e' la stessa che vanilla mette sulle note della
    -- mappa, quindi un biglietto qui e uno la' si somigliano davvero.
    local textStyle = self.textAPI:getStyleAPI()
    local layer = textStyle and textStyle:newTextLayer(LAYER)
    if layer then
        layer:setFont(UIFont.Handwritten)
        layer:addFill(0.0, 0.0, 0.0, 0.0, 255.0)
    else
        -- Senza livello non c'e' niente da disegnare: i biglietti tornano
        -- dritti e la pagina non se ne accorge.
        self.works = false
    end

    self.items = {}
    self:createChildren()
end

--- Quello che va disegnato in questo fotogramma. Lo riempie NW_Page nel suo
--- prerender; qui si consuma e basta.
function NW_TextLayer:clear()
    self.items = {}
end

function NW_TextLayer:add(text, cx, cy, degrees, scale, r, g, b, a)
    self.items[#self.items + 1] = {
        text = text, x = cx, y = cy, deg = degrees or 0, scale = scale or 1,
        r = r, g = g, b = b, a = a or 1,
    }
end

--- I biglietti, girati.
---
--- Il primo tentativo decide: se il motore rifiuta la chiamata - un id di
--- livello che non gli piace, una versione che l'ha spostata - `works` diventa
--- falso e NW_Page torna a disegnarli dritti. Si perde la rotazione, non un
--- biglietto.
function NW_TextLayer:render()
    if self.works == false then return end
    if not self.items or #self.items == 0 then return end

    for _, it in ipairs(self.items) do
        -- Ancora al centro: e' anche il perno della rotazione, e un biglietto
        -- che gira attorno al proprio centro e' quello che ci si aspetta.
        local ok = pcall(function()
            self.javaObject:DrawTextSdfRotated(LAYER, it.text, it.x, it.y,
                0.5, 0.5, it.deg, it.scale, false, false, it.r, it.g, it.b, it.a)
        end)
        if not ok then
            self.works = false
            return
        end
    end
    self.works = true
end

-- Il mouse non passa di qui: la pagina sta sotto ed e' lei a lavorare.
function NW_TextLayer:onMouseDown() return false end
function NW_TextLayer:onMouseUp() return false end
function NW_TextLayer:onMouseMove() return false end
function NW_TextLayer:onMouseWheel() return false end
function NW_TextLayer:onRightMouseDown() return false end

function NW_TextLayer:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.moveWithMouse = false
    o.items = {}
    return o
end

return NW_TextLayer
