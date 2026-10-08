--[[ ============================================================================
    NW_Reading - locandine, brochure e giornali dentro una cornice nostra.

    IL FOGLIO E' DI VANILLA, LA CORNICE NO. La carta e' una scena di testo ricco
    - texture ruotate, caratteri SDF, un pivot per elemento - che il gioco monta
    con il suo sistema di nodi (PZAPI.UI.PrintMedia) leggendo una stringa di
    markup. Rifarne il lettore vorrebbe dire riscrivere quel parser per
    ridisegnare la stessa identica carta: il foglio resta suo, ed e' giusto
    cosi'. Tutto il resto della finestra invece se ne va.

    PERCHE' SE NE VA TUTTO. Per un po' la finestra di vanilla e' stata vestita:
    alle sue nodi si davano le nostre texture, i nostri colori, le nostre
    misure. Funzionava per quasi tutto e continuava a non funzionare per una
    cosa - i bordi. Una cornice della famiglia e' una NinePatchTexture, quattro
    angoli che non si deformano mai e un centro che si allunga, e un nodo PZAPI
    non la sa disegnare: gli si puo' dare la texture e uno slice, ma quello che
    ne esce non e' un nine-patch nostro. Da li' i bordi irregolari in alto e
    nell'header, che nessuna misura di slice ha mai raddrizzato del tutto.

    Adesso la cornice e' un ISPanel (NW_ReadWindow), cioe' il posto dove
    NW_Style.drawWindow - la stessa riga che disegna il pannello Writing e la
    configurazione di XP Drop - funziona senza trucchi. Alla finestra di vanilla
    restano il foglio e niente altro.

    DUE PASSATE, e la divisione conta:

      layout()   modifica il TEMPLATE, una volta, prima che qualcuno lo
                 istanzi. E' l'unico momento in cui si possono toccare le
                 ancore e le altezze: un nodo le legge quando nasce e mai piu'.
                 Qui le tre strisce di cornice - barra, tasti, fondo - vanno a
                 zero, cosi' updateSize misura la finestra sul solo foglio.

      restyle()  gira su ogni finestra dopo che e' stata costruita: spegne
                 quelle tre strisce e le mette attorno la nostra.

    COSA VA VIA E PERCHE':
      info        non faceva niente: il suo onLeftClick suona e basta
      settings    apriva un secondo tooltip con le opzioni della finestra
      pin         chiudeva la finestra a fisarmonica, cosa che i nostri
                  pannelli non fanno
      notebook    la trascrizione, un muro di testo sopra la carta

    COSA RESTA: il foglio, la X, e i tasti che svelano un luogo sulla mappa -
    spostati nell'header, dove il pannello li disegna come tasti nostri.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Config"
require "NeatWriting/NW_Style"
require "NeatWriting/UI/NW_ReadWindow"

-- I file client si caricano in ordine di percorso, e "NeatWriting" viene prima
-- di "PZAPI": senza questo require PrintMedia non esisterebbe ancora e il
-- controllo qui sotto ci manderebbe a casa per sempre.
pcall(require, "PZAPI/ui/organisms/PrintMedia")

if not (PZAPI and PZAPI.UI and PZAPI.UI.PrintMedia and PZAPI.UI._mt) then return end

NW_Reading = NW_Reading or {}
local R = NW_Reading

local UI = PZAPI.UI

--- Toglie a un nodo UI.Panel i suoi quattro bordi da un pixel.
---
--- Panel li costruisce come figli e li dipinge grigi nel suo init: erano loro a
--- tracciare le righe pallide lungo i lati. Colorarli trasparenti li lasciava
--- li' pronti a essere ricolorati; toglierli dal template vuol dire che non
--- nascono proprio.
---
--- Toglierli e' solo meta' del lavoro. Panel ha
---     setBorderColor = function(self, r, g, b, a)
---         self.children.leftBorder:setColor(r, g, b, a)
--- e quel suo init continuava a cercare figli che non c'erano piu', tirando
--- "attempted index: setColor of non-table: null" all'apertura. Chi li dipinge
--- se ne va con loro.
local function noBorders(node)
    if not node or not node.children then return end
    node.children.leftBorder = nil
    node.children.rightBorder = nil
    node.children.topBorder = nil
    node.children.downBorder = nil
    node.setBorderColor = function() end
end

local function hide(node)
    if not node then return end
    pcall(function()
        node:setVisible(false)
        node:setEnabled(false)
    end)
end

-- ---------------------------------------------------------------------------
-- Il template: tutto quello che e' un'ancora o un'altezza
-- ---------------------------------------------------------------------------

--- Riscrive PZAPI.UI.PrintMedia prima che venga istanziata.
---
--- Le tre strisce di cornice vanno a zero e il corpo prende tutta la finestra.
--- updateSize misura cosi':
---     setHeight(foglio + bar.height + bottomButtons.height + bottomBar.height)
--- e con le tre a zero la finestra diventa esattamente il foglio - che e'
--- quello che ci serve, perche' la cornice attorno la mettiamo noi e vogliamo
--- sapere con precisione quanto e' grande la carta.
local function layout()
    local PM = UI.PrintMedia

    noBorders(PM.children.bar)
    noBorders(PM.children.body)
    noBorders(PM.children.bottomButtons)
    noBorders(PM.children.bottomBar)

    PM.children.bar.height = 0
    PM.children.bottomButtons.height = 0
    PM.children.bottomBar.height = 0

    PM.children.body.anchorTop = 0
    PM.children.body.anchorDown = 0
end

-- ---------------------------------------------------------------------------
-- La finestra: spogliarla, e metterle attorno la nostra
-- ---------------------------------------------------------------------------

function R.restyle(win)
    local kids = win.children or {}
    local body = kids.body
    local strip = kids.bottomButtons

    -- Il corpo non dipinge niente: la carta si porta dietro la sua.
    if body then
        pcall(function() body:setColor(0, 0, 0, 0) end)
        if body.setBorderColor then pcall(function() body:setBorderColor(0, 0, 0, 0) end) end
    end

    -- La trascrizione va CHIUSA prima di sparire. Nascondere solo il suo tasto
    -- lascerebbe il muro di testo sopra la carta e nessun modo di toglierlo.
    if strip and strip.children then
        local notebook = strip.children.readNewspaper
        if notebook and notebook.isClosed == false then
            pcall(function() notebook:onLeftClick() end)
        end
    end

    -- La cornice, costruita prima di spegnere le strisce: e' li' dentro che si
    -- legge quali tasti mappa questo documento ha davvero.
    local title = win.textTitle
    if (not title or title == "") and kids.bar and kids.bar.children and kids.bar.children.name then
        title = kids.bar.children.name.text
    end
    NW_ReadWindow.wrap(win, title)

    -- E adesso via tutto quello che non e' il foglio. I nodi restano vivi -
    -- i tasti mappa portano con se' la funzione che svela il luogo, e la
    -- cornice la chiama - ma non si vedono e non prendono il mouse.
    hide(kids.bar)
    hide(strip)
    hide(kids.bottomBar)
end

-- ---------------------------------------------------------------------------
-- Il subentro
-- ---------------------------------------------------------------------------

pcall(layout)

--- La cornice va costruita dopo che l'albero esiste tutto, e instantiate() e'
--- l'unica chiamata che lo garantisce: costruisce gli oggetti Java, fa girare
--- l'init di ogni nodo e il suo onResize, e solo allora consegna la finestra a
--- UIManager.
---
--- I due posti da cui vanilla apre una stampa - ISWorldMap:onMouseUpPrintMedia
--- e ISReadABook - passano tutti e due di qui, quindi nessuno dei due va
--- toccato.
local baseInstantiate = UI._mt.instantiate

UI.PrintMedia.instantiate = function(self)
    baseInstantiate(self)
    -- Una cornice che non riesce a nascere non deve costare al giocatore la
    -- finestra stessa.
    local ok, err = pcall(R.restyle, self)
    if not ok then print("NW_Reading: " .. tostring(err)) end
end

return NW_Reading
