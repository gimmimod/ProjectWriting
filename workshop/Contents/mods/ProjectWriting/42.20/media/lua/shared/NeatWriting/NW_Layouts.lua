--[[ ============================================================================
    NW_Layouts - i supporti su cui si scrive, e com'e' fatto ognuno.

    Un supporto e' un'immagine piu' le sue misure: quanto e' grande, quante
    facciate mostra e dove, su ognuna, si puo' scrivere.

    QUALI OGGETTI. Vanilla dichiara CanBeWrite su diciannove voci e il menu
    contestuale le filtra con

        getCategory() == "Literature" and canBeWrite()

    Attenzione a non confondere getCategory() con DisplayCategory: il primo
    viene da ItemType, e tutte e diciannove hanno ItemType = base:literature.
    Passano tutte. Quali meritino una pagina vera e' una scelta nostra, ed e'
    L.forItem a farla tornando nil per il resto.

    UNA O DUE FACCIATE. Blocco, foglio, carta a quadretti e scheda ne hanno una;
    quaderni e diari si aprono e ne mostrano due. Una facciata e' una pagina di
    vanilla: la facciata k dell'apertura s e' la pagina (s-1)*sheets + k, ed e'
    quello che tiene insieme il nostro testo e quello che il gioco sa gia'
    leggere.

    LE MISURE SONO MISURATE, non stimate: le stampa
    art/aree-pagine.js scandendo i pixel delle immagini originali, e
    art/verifica-aree.png fa vedere dove sono finite.

      * i riquadri di carta vengono dalle colonne abbastanza chiare e opache;
      * la spirale del blocco sta sopra al primo riquadro e ne resta fuori da
        sola, perche' il metallo non e' carta;
      * fra le due facciate di un diario la carta NON si interrompe - si
        incurva - quindi la piega si trova come avvallamento di luminosita' e si
        toglie una fascia di circa il 6% della larghezza, la stessa che la
        spirale del quaderno toglie per conto suo.

    LA SCRITTURA. Si scrive sempre in Handwritten, che e' alta quaranta pixel e
    non cambia mai (NW_Writer). Il descrittore quindi non sceglie un carattere:
    dice solo dove sono le RIGHE STAMPATE, dove ce ne sono.

    `ruled` marca le carte che ne hanno; `line` e' il loro passo e `first` il
    fondo della prima, tutti e due misurati sui pixel dell'immagine: 33.38 e 140
    per il quaderno a righe, 37.36 e 89 per la scheda, 33 e 61 per il quadretto
    della carta a quadretti. Su quelle carte la scrittura si aggancia al passo
    stampato, o a un suo multiplo se la grafia e' piu' alta.

    Sulla carta senza righe niente di tutto questo serve: il passo e' l'altezza
    della grafia e la prima riga sta sotto il margine. `line` li' resta come
    numero di riferimento e non lo legge nessuno.

    I MARGINI SONO DUE. `margin` e' quello ai lati, `marginY` quello sopra e
    sotto; dove manca il secondo vale il primo. Sui fogli larghi non possono
    essere lo stesso numero: la carta a quadretti toglie 226 unita' per lato
    perche' una riga lunga quanto il foglio non si legge, ma toglierne 226 anche
    sopra e sotto lascia un francobollo in mezzo alla pagina. E' stato per un po'
    il riquadro di scrittura della scheda, e da fuori sembrava tutt'altro: il
    cursore che non andava dove si cliccava, e Invio che non andava a capo.

    LE PAGINE. `pages` e' quante ne offriamo, che sono piu' di quelle di
    vanilla: cinque pagine su un blocco a spirale sono poche, e il gioco non ha
    un modo per cambiarle senza riscrivere i suoi script. Le prime restano dove
    le mette vanilla - cosi' si leggono anche senza la mod - e le altre stanno
    nel nostro modData. Se un giorno vanilla ne dichiarasse di piu', vince lui.
============================================================================ ]]--

NW_Layouts = NW_Layouts or {}
local L = NW_Layouts

local TEX = "media/textures/NeatWriting/"

--- Gli strumenti che hanno senso su un foglio. Sono tutti, su tutti: anche una
--- scheda o un foglio a quadretti si scrivono a righe, e la carta senza righe
--- stampate non e' un motivo per togliere la scrittura lineare - il passo lo
--- decide `line`, non la carta.
local ALL = { draw = true, note = true, symbol = true, text = true }

L.MEDIA = {
    -- Foglio strappato, una facciata.
    sheet = {
        id = "sheet", texture = TEX .. "Page_Sheet.png",
        width = 1024, height = 1536, tools = ALL, sheets = 1,
        areas = { { 32, 46, 991, 1491 } },
        text = { line = 46, margin = 40 },
        pages = 2,
    },
    -- Blocco a spirale, una facciata. Gli anelli stanno sopra y=106.
    notepad = {
        id = "notepad", texture = TEX .. "Page_Notepad.png",
        width = 1070, height = 1470, tools = ALL, sheets = 1,
        areas = { { 54, 106, 1016, 1370 } },
        text = { line = 46, margin = 36 },
        pages = 20,
    },
    -- Quaderno a spirale aperto, due facciate: la spirale le separa gia'.
    notebook = {
        id = "notebook", texture = TEX .. "Page_Notebook.png",
        width = 1448, height = 1086, tools = ALL, sheets = 2,
        areas = { { 58, 67, 678, 995 }, { 768, 67, 1388, 995 } },
        text = { line = 32, margin = 28 },
        pages = 40,
    },
    -- Lo stesso quaderno, ma a righe: il passo e' quello stampato.
    notebook_lines = {
        id = "notebook_lines", texture = TEX .. "Page_NotebookLines.png",
        width = 1448, height = 1086, tools = ALL, sheets = 2,
        areas = { { 57, 69, 679, 994 }, { 769, 69, 1389, 994 } },
        text = { line = 33.38, margin = 28, first = 140, ruled = true },
        pages = 30,
    },
    -- Diario blu, due facciate. La piega e' a 767, tolti 95 px.
    diary_blue = {
        id = "diary_blue", texture = TEX .. "Page_DiaryBlue.png",
        width = 1536, height = 1024, tools = ALL, sheets = 2,
        areas = { { 64, 64, 719, 945 }, { 815, 66, 1472, 945 } },
        text = { line = 32, margin = 30 },
        pages = 80,
    },
    -- Diario rosso, due facciate. La piega e' a 723, tolti 90 px.
    diary_red = {
        id = "diary_red", texture = TEX .. "Page_DiaryRed.png",
        width = 1448, height = 1086, tools = ALL, sheets = 2,
        areas = { { 51, 96, 678, 933 }, { 768, 97, 1396, 933 } },
        text = { line = 32, margin = 28 },
        pages = 80,
    },
    -- Carta a quadretti: il passo di scrittura e' il quadretto, 33.
    graph_paper = {
        id = "graph_paper", texture = TEX .. "Page_GraphPaper.png",
        width = 1536, height = 1024, tools = ALL, sheets = 1,
        areas = { { 34, 28, 1503, 996 } },
        text = { line = 33, margin = 226, marginY = 40, first = 89, ruled = true },
        pages = 2,
    },
    -- Scheda: un foglio a righe, non il cartoncino bianco della prima versione.
    -- Le righe stampate ci sono davvero, quindi la scrittura ci si appoggia
    -- sopra come sul quaderno. Passo e prima riga sono meno regolari di quelli
    -- del quaderno perche' la carta e' fotografata: 37.36 e' la media fra la
    -- prima riga e la ventitreesima.
    index_card = {
        id = "index_card", texture = TEX .. "Page_IndexCard.png",
        width = 1536, height = 1024, tools = ALL, sheets = 1,
        areas = { { 22, 10, 1518, 1005 } },
        text = { line = 37.36, margin = 240, marginY = 40, first = 89, ruled = true },
        pages = 4,
    },
    -- Il biglietto: un foglio bianco piegato e riaperto, orizzontale. Una
    -- facciata sola - la piega si vede ma non interrompe la carta, quindi non
    -- divide niente - e nessuna riga stampata su cui agganciarsi.
    --
    -- Il margine orizzontale e' piu' stretto di quello della scheda perche' qui
    -- non serve tenerlo largo: il tetto di battute per riga (NW_Page) stringe e
    -- centra la riga da se' quando il foglio e' grande, e su uno schermo piccolo
    -- cosi' si usa piu' carta.
    card = {
        id = "card", texture = TEX .. "Page_Card.png",
        width = 1536, height = 1024, tools = ALL, sheets = 1,
        areas = { { 46, 41, 1491, 979 } },
        text = { line = 46, margin = 120, marginY = 40 },
        pages = 2,
    },
}

--- Oggetto del gioco -> supporto. Quello che non e' qui apre la finestra di
--- vanilla, e va bene cosi'.
L.BY_ITEM = {
    Notepad     = "notepad",         -- 5 pagine
    Notebook    = "notebook_lines",  -- 10
    Journal     = "notebook",        -- 20
    Diary1      = "diary_blue",      -- 40
    Diary2      = "diary_red",       -- 40
    SheetPaper2 = "sheet",           -- 1
    GraphPaper  = "graph_paper",     -- 1
    IndexCard   = "index_card",      -- 1

    -- I BIGLIETTI. Erano gli undici oggetti scrivibili rimasti fuori, e ne
    -- restavano fuori per mancanza di un disegno, non di codice: vanilla li
    -- dichiara CanBeWrite come gli altri otto e li apriva col suo campo di
    -- testo. Adesso il disegno c'e' - un foglio bianco piegato e riaperto - e
    -- ci vanno tutti sopra.
    --
    -- L'IDcard_Blank ci sta per la stessa ragione per cui vanilla la considera
    -- scrivibile: e' una tessera vuota su cui si scrive. La carta e' quella del
    -- biglietto perche' un'altra non ce n'e'.
    MenuCard       = "card",
    Card_Birthday  = "card",
    Card_Christmas = "card",
    Card_Easter    = "card",
    Card_Halloween = "card",
    Card_Hanukkah  = "card",
    Card_LunarYear = "card",
    Card_StPatrick = "card",
    Card_Sympathy  = "card",
    Card_Valentine = "card",
    IDcard_Blank   = "card",
}

--- Il supporto di un oggetto, o nil se non lo gestiamo noi.
---
--- Il tipo si chiede in due modi perche' getType() da' "Notepad" e
--- getFullType() da' "Base.Notepad", e a seconda di chi ce lo passa arriva
--- l'uno o l'altro.
function L.forItem(item)
    if not item then return nil end
    local ok, full = pcall(function() return item:getFullType() end)
    if ok and full then
        local short = full:match("[^%.]+$")
        local key = L.BY_ITEM[short] or L.BY_ITEM[full]
        if key then return L.MEDIA[key] end
    end
    local ok2, t = pcall(function() return item:getType() end)
    if ok2 and t and L.BY_ITEM[t] then return L.MEDIA[L.BY_ITEM[t]] end
    return nil
end

--- L'area di carta numero `n`, in coordinate pagina: x0, y0, x1, y1.
function L.area(media, n)
    local a = media.areas[n or 1]
    if not a then return 0, 0, media.width, media.height end
    return a[1], a[2], a[3], a[4]
end

--- Quante facciate mostra un'apertura di questo supporto.
function L.areaCount(media)
    return #media.areas
end

--- L'area che contiene un punto, o nil se il punto e' sulla rilegatura, sugli
--- anelli o fuori dalla carta. E' cosi' che un tratto non attraversa la piega.
function L.areaAt(media, px, py)
    for i, a in ipairs(media.areas) do
        if px >= a[1] and px <= a[3] and py >= a[2] and py <= a[4] then return i end
    end
    return nil
end

--- Il riquadro in cui scorre il testo: l'area meno i suoi margini.
---
--- Il margine orizzontale e quello verticale sono due numeri diversi, e lo sono
--- per forza. Su un foglio largo la riga va accorciata o diventa illeggibile -
--- la carta a quadretti ne toglie 226 unita' per lato - ma togliere altrettanto
--- sopra e sotto lascia un francobollo in mezzo alla pagina: era il riquadro di
--- scrittura della scheda, piccolo e centrato, e il cursore non arrivava dove
--- si cliccava perche' fuori da quel rettangolo non c'era niente da cliccare.
function L.textBox(media, n)
    local x0, y0, x1, y1 = L.area(media, n)
    local t = media.text or {}
    local mx = t.margin or 30
    local my = t.marginY or mx
    return x0 + mx, y0 + my, x1 - mx, y1 - my
end

--- La scala a cui mostrare la pagina, agganciata alle righe stampate.
---
--- La grafia e' alta 40 pixel e non si puo' cambiare: il riquadro di scrittura
--- di vanilla incolonna le righe a quell'altezza e basta. Le righe STAMPATE
--- invece si muovono con la pagina, e allora e' la pagina che si adatta a loro:
--- se esiste una scala, non troppo piu' piccola di quella che riempie lo
--- schermo, a cui una riga stampata (o due, o tre) misura esattamente 40 pixel,
--- si prende quella e il testo cade sopra le righe per tutta la facciata invece
--- che solo sulla prima.
---
--- Sotto l'85% la pagina rimpicciolirebbe troppo per il guadagno - a 1080p il
--- quaderno a righe dovrebbe scendere a due terzi - e allora si tiene la scala
--- piena: la prima riga resta agganciata lo stesso, le altre no.
function L.pageScale(media, fit, pitch)
    local t = media.text or {}
    if not t.ruled or not t.line or t.line <= 0 then return fit end
    if not pitch or pitch <= 0 or not fit or fit <= 0 then return fit end
    for n = 1, 4 do
        local s = pitch / (t.line * n)
        if s <= fit then
            if s >= fit * 0.85 then return s end
            return fit
        end
    end
    return fit
end

--- Il passo di scrittura, in unita' pagina.
function L.line(media)
    return (media.text and media.text.line) or 40
end

--- Dove cade il FONDO della prima riga di scrittura.
---
--- Dove la carta ha righe stampate e' la prima di quelle, misurata: cosi' il
--- testo ci si appoggia sopra invece di galleggiarci accanto. Dove non ne ha,
--- e' una riga sotto il margine.
function L.firstLine(media, n)
    local t = media.text or {}
    if t.first then return t.first end
    local _, y0 = L.area(media, n)
    return y0 + (t.marginY or t.margin or 30) + L.line(media)
end

--- Quante pagine ha questo oggetto: le nostre, o quelle di vanilla se sono di
--- piu'. Non si tolgono mai pagine a un oggetto che ne dichiara gia' tante.
function L.pageCount(media, vanillaPages)
    return math.max(vanillaPages or 1, media.pages or 1)
end

--- Quante aperture servono per `pages` pagine di vanilla.
function L.spreads(media, pages)
    return math.max(1, math.ceil(math.max(1, pages or 1) / #media.areas))
end

--- La pagina di vanilla mostrata nella facciata `n` dell'apertura `spread`.
function L.pageOf(media, spread, n)
    return (spread - 1) * #media.areas + n
end

return NW_Layouts
