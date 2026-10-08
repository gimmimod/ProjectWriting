--[[ ============================================================================
    NW_Config - the numbers and names every other NeatWriting file reads.

    Ink colours are vanilla's own (ISWorldMapSymbols.colorButtonInfo), so a mark
    made through this panel is the same colour as one made through the vanilla
    one. Tool tags are the item tags from media/scripts/generated/items, which is
    what makes third-party pens work without naming them.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Categories"
require "NeatWriting/NW_Net"

NW = NW or {}

NW.VERSION = 1
NW.ICONS = "media/ui/NeatWriting/"

-- ---------------------------------------------------------------------------
-- Ink
-- ---------------------------------------------------------------------------
-- Every entry: the tag that grants it, the fallback item types for builds or
-- mods that carry no tag, and the colour it writes in.
--
-- `slot` e' lo stesso inchiostro come riempie la casella dello strumento nel
-- pannello (NW_Style.drawSlot). E' quel colore, non un altro: rosso, blu e verde
-- sono gli stessi un filo piu' accesi, perche' dietro una texture a meta'
-- trasparenza su un pannello scuro il colore vero si spegne. Il nero e' piu'
-- nero di quello della carta: a 0.13 la casella era identica a quella vuota di
-- una gomma. Nero e matita sulla carta sono quasi lo stesso grigio scuro (0.13 e
-- 0.20): nella casella la matita e' grafite, un grigio chiaro e freddo, o le
-- caselle di nero, matita e gomma sarebbero tre grigi uguali. Misurati su
-- un'anteprima composta come fa il motore, non a occhio sul numero.
NW.INKS = {
    { id = "black",  tag = "base:pen",      r = 0.129, g = 0.129, b = 0.129,
      types = { "Pen", "PenFancy", "PenSpiffo", "MarkerBlack", "PenMultiColor", "Crayons" },
      label = "IGUI_NW_InkBlack",
      slot = { r = 0.04, g = 0.04, b = 0.05 } },
    { id = "pencil", tag = "base:pencil",   r = 0.200, g = 0.200, b = 0.200,
      types = { "Pencil", "PencilSpiffo", "Crayons" },
      label = "IGUI_NW_InkPencil",
      slot = { r = 0.47, g = 0.50, b = 0.56 } },
    { id = "red",    tag = "base:redpen",   r = 0.650, g = 0.054, b = 0.054,
      types = { "RedPen", "MarkerRed", "PenMultiColor", "Crayons" },
      label = "IGUI_NW_InkRed",
      slot = { r = 0.66, g = 0.08, b = 0.08 } },
    { id = "blue",   tag = "base:bluepen",  r = 0.156, g = 0.188, b = 0.490,
      types = { "BluePen", "MarkerBlue", "PenMultiColor", "Crayons" },
      label = "IGUI_NW_InkBlue",
      slot = { r = 0.20, g = 0.25, b = 0.62 } },
    { id = "green",  tag = "base:greenpen", r = 0.060, g = 0.390, b = 0.170,
      types = { "GreenPen", "MarkerGreen", "PenMultiColor", "Crayons" },
      label = "IGUI_NW_InkGreen",
      slot = { r = 0.09, g = 0.47, b = 0.22 } },
}

NW.ERASER = {
    tag = "base:eraser",
    -- Pencil carries base:eraser too: the rubber on the end of it.
    types = { "Eraser", "Pencil" },
    label = "IGUI_NW_Eraser",
}

-- An item can be tagged base:write without saying which colour it lays down.
-- Those still belong in the strip: they write in black.
NW.WRITE_TAG = "base:write"

-- ---------------------------------------------------------------------------
-- Tools (the row of function buttons)
-- ---------------------------------------------------------------------------
-- `word` marks the one that needs a page to anchor to: on the map it is left
-- out, and the row simply closes up. One table, read in one place - no
-- "if we are on the map" scattered through the UI.
NW.TOOLS = {
    { id = "draw",   icon = "Pen.png",     label = "IGUI_NW_ToolDraw" },
    { id = "text",   icon = "Text.png",    label = "IGUI_NW_ToolText",   word = true },
    { id = "note",   icon = "TextBox.png", label = "IGUI_NW_ToolNote" },
    { id = "symbol", icon = "Symbols.png", label = "IGUI_NW_ToolSymbol" },
}

-- ---------------------------------------------------------------------------
-- Brush
-- ---------------------------------------------------------------------------
-- Actions on whatever is already on the page. Vanilla keeps move and rotate as
-- separate tools and hides scale inside the edit dialog; we keep the same three
-- so the habits transfer, in their own row under the function buttons.
NW.ACTIONS = {
    { id = "move",   icon = "Move.png",   label = "IGUI_NW_ActMove" },
    { id = "rotate", icon = "Rotate.png", label = "IGUI_NW_ActRotate" },
    { id = "edit",   icon = "Resize.png", label = "IGUI_NW_ActEdit" },
}

NW.BRUSH = {
    MIN = 1.0,
    MAX = 9.0,
    DEFAULT = 3.0,
}

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
-- Two widths. A paper map is a small window and cannot spare much; the world
-- map is full screen and both affords and wants a roomier panel - the symbol
-- sheet in particular reads far better six or seven columns wide.
NW.PANEL_W = 286
NW.PANEL_W_WIDE = 360
-- Il pannello piu' stretto che ha senso a scala 1: la riga di tasti piu' lunga
-- (quattro strumenti da 34 con 14 di passo, 178) piu' i due margini da 10.
-- Sotto questa i tasti uscirebbero dal bordo. Scala con il contenuto.
NW.PANEL_MIN_W = 200
NW.PAD = 10

-- ---------------------------------------------------------------------------
-- Symbol sheet: tab names
-- ---------------------------------------------------------------------------
-- The sheet files symbols by what they are, not by which mod brought them:
-- NW_Categories holds that taxonomy and this only turns a tab into a word.
--
-- A symbol from a mod we have never seen keeps the tab it declared, so it is
-- never dropped - it just lands after ours, under whatever name it came with.

--- Where a tab sits in the sheet. Unknown tabs go last, alphabetically.
function NW.tabRank(tab)
    return NW_Categories.rank(tab)
end

--- What to print on a tab. One of ours gets its own name; anything else keeps
--- whatever the game can translate, and failing that its raw name.
function NW.tabLabel(tab)
    local key = NW_Categories.LABELS[tab]
    if key then
        local text = getText(key)
        if text ~= key then return text end
    end
    local vanilla = getText("IGUI_Map_Tab" .. tab)
    if vanilla ~= "IGUI_Map_Tab" .. tab and vanilla ~= tab then return vanilla end
    return tab
end

-- ---------------------------------------------------------------------------
-- Preferences
-- ---------------------------------------------------------------------------

--- Which symbol packs appear in the sheet. Written by NW_ModOptions, read by
--- the sheet. The AddMoreMapSymbols set is off by default: it is 95 tiles, and
--- a sheet nobody asked to grow should not grow.
---
--- The symbols are registered either way. MapSymbolDefinitions is loaded once,
--- shared, and long before the options screen can be asked anything; and a
--- symbol already drawn on a saved map has to keep its texture even after the
--- player turns its pack off. So the switch is on the sheet, which is the only
--- place they can be picked from.
---
--- A symbol from some other mod belongs to no pack of ours and is always shown.
NW.packs = {
    [NW_Categories.PACK_VANILLA] = true,
    [NW_Categories.PACK_EXTRA]   = true,
    -- Off, unless the player installed Add More Map Symbols themselves: hiding
    -- a set somebody deliberately subscribed to would just look broken.
    [NW_Categories.PACK_AMMS]    = NW_Categories.ammsModInstalled(),
}

--- Whether a symbol should be offered, given the packs that are on.
function NW.packEnabled(id, texturePath)
    local pack = NW_Categories.packOf(id, texturePath)
    if not pack then return true end
    return NW.packs[pack] ~= false
end

--- One string that changes whenever the answer above would change, so the sheet
--- can tell it has to be rebuilt without comparing three booleans by hand.
function NW.packSignature()
    return tostring(NW.packs[NW_Categories.PACK_VANILLA]) .. "|"
        .. tostring(NW.packs[NW_Categories.PACK_EXTRA]) .. "|"
        .. tostring(NW.packs[NW_Categories.PACK_AMMS])
end

-- ---------------------------------------------------------------------------
-- Le tre preferenze che cambiano il comportamento
-- ---------------------------------------------------------------------------
--
-- Le scrive NW_ModOptions, le leggono le patch. Il valore sta qui e non li'
-- perche' Mod Options e' una mod di qualcun altro: senza, questi restano i
-- valori di partenza e tutto funziona lo stesso.
--
-- Si leggono SEMPRE al momento in cui servono, mai copiate al caricamento: il
-- giocatore puo' cambiarle a meta' partita, e una copia presa all'avvio
-- direbbe per sempre com'era il mondo allora.
NW.prefs = NW.prefs or {
    -- La mappa resta quella del gioco, con i suoi pannelli e le sue
    -- funzioni di condivisione. Pensata per i server che ci hanno costruito
    -- sopra: i pacchetti di simboli restano, tutto il resto no.
    vanillaMap = false,
    -- Il mondo si ferma mentre si scrive.
    pause = true,
    -- Le note si possono spartire con gli altri.
    share = true,
    -- La mappa del mondo non ferma il gioco quando si apre. Spenta di
    -- partenza: decide l'opzione di vanilla, come prima.
    mapNoPause = false,
    -- Misura e angolo di un segno con Ctrl/Shift + rotella mentre lo si posa
    -- (NW_Placing).
    placeAdjust = true,
    -- Il tetto di battute per facciata scelto dal giocatore; 0 = nessuno.
    pageLimit = 0,
}

--- Quante battute al massimo su una facciata, o 0 se non c'e' tetto.
---
--- La sandbox vince: su un server di gioco di ruolo il tetto lo decide chi lo
--- gestisce, e deve valere per tutti allo stesso modo - e' proprio la
--- differenza fra uno e l'altro schermo che fa perdere il testo a chi legge.
--- A sandbox spenta (0) decide ognuno per se', dalle opzioni della mod.
function NW.pageCharLimit()
    local sv = SandboxVars and SandboxVars.ProjectWriting
    local forced = sv and tonumber(sv.PageCharLimit) or 0
    if forced and forced > 0 then return math.floor(forced) end
    return math.max(0, math.floor(tonumber(NW.prefs.pageLimit) or 0))
end

--- La mappa lasciata al gioco: per scelta del giocatore (opzioni della mod) o
--- perche' la partita lo impone a tutti (opzione sandbox, NW_Net). La sandbox
--- vince: su un server che l'ha accesa la spunta personale non conta.
function NW.vanillaMap()
    return NW_Net.vanillaMapForced() or NW.prefs.vanillaMap == true
end
function NW.pauseWhileWriting() return NW.prefs.pause ~= false end

--- Spartire le note con gli altri, o tenersele.
---
--- Spegnerlo non e' come mettere "solo io" nel pannello: quello e' una scelta
--- che si cambia, questo toglie di mezzo la funzione: il tasto con
--- l'aeroplanino sparisce e niente parte piu' per il server, nemmeno per
--- sbaglio. Per chi la mod la vuole solo per scrivere.
function NW.sharing() return NW.prefs.share ~= false end

-- ---------------------------------------------------------------------------
-- La misura del pannello
-- ---------------------------------------------------------------------------
--
-- Non e' una preferenza da schermata delle opzioni: si prende la maniglia
-- d'angolo e si tira, come sulla barra di XP Drop. Quello che si e' scelto
-- resta, quindi va scritto da qualche parte - un file di due righe accanto a
-- quello di XP Drop, che e' dove il gioco tiene le impostazioni di una mod
-- che non passano dal salvataggio.
--
-- A 4K il pannello disegnato a 360 pixel e' un francobollo: e' da li' che
-- arriva questa maniglia.
NW.SCALE = { MIN = 0.8, MAX = 2.5, DEFAULT = 1.0 }

local INI = "ProjectWriting.ini"
local scale = nil

local function clampScale(s)
    s = tonumber(s) or NW.SCALE.DEFAULT
    if s < NW.SCALE.MIN then return NW.SCALE.MIN end
    if s > NW.SCALE.MAX then return NW.SCALE.MAX end
    return s
end

--- Il tetto che lo schermo impone: meta' della sua larghezza, misurata sul
--- pannello piu' largo che apriamo. Serve a chi si porta la partita da un
--- monitor grande a uno piccolo - la misura salvata resta quella, ma qui non
--- puo' fare danni.
local function screenCap()
    local room = getCore():getScreenWidth() * 0.5
    -- Sulla larghezza MINIMA, non su quella di progetto: da quando larghezza e
    -- scala sono due numeri, ingrandire il contenuto non costringe piu' il
    -- pannello ad allargarsi nella stessa proporzione.
    return math.max(NW.SCALE.MIN, math.min(NW.SCALE.MAX, room / NW.PANEL_MIN_W))
end

--- Quanto e' grande il pannello, da 1 in su. Letta dal file la prima volta che
--- qualcuno la chiede, e da li' in poi tenuta a mente.
--- Tutto il file, letto una volta sola. Chiave -> valore, come stringhe.
---
--- SI LEGGE E SI RISCRIVE PER INTERO, e da quando le chiavi sono due non e'
--- pedanteria: `getFileWriter` con `true` tronca il file, quindi salvare una
--- sola riga cancellava tutte le altre. Con una chiave non si vedeva; con due
--- avrebbe voluto dire che scegliere la mappa scura azzerava la misura del
--- pannello, e viceversa, a seconda di chi salvava per ultimo.
local prefsFile = nil

local function readPrefs()
    if prefsFile then return prefsFile end
    prefsFile = {}
    local f = getFileReader(INI, false)
    if f then
        local line = f:readLine()
        while line ~= nil do
            local p = string.split(line, "=")
            if p and #p == 2 then prefsFile[p[1]] = p[2] end
            line = f:readLine()
        end
        f:close()
    end
    return prefsFile
end

local function writePrefs()
    local f = getFileWriter(INI, true, false)
    if not f then return end
    for k, v in pairs(prefsFile or {}) do
        f:write(k .. "=" .. tostring(v) .. "\n")
    end
    f:close()
end

function NW.panelScale()
    if scale then return math.min(scale, screenCap()) end
    scale = clampScale(readPrefs().panel_scale or NW.SCALE.DEFAULT)
    return math.min(scale, screenCap())
end

--- La mappa del mondo in notturna.
---
--- Sta nel file e non nella modData: e' una preferenza di chi guarda, non un
--- fatto del personaggio - vale su tutte le partite e non si eredita morendo,
--- esattamente come la misura del pannello.
function NW.darkMap()
    return readPrefs().dark_map == "1"
end

function NW.setDarkMap(on)
    readPrefs().dark_map = on and "1" or "0"
    writePrefs()
    return on
end

--- La notte che si accende da sola quando cala il buio nel mondo.
---
--- E' una preferenza, non un interruttore: dice a chi accende la luce, non
--- quale luce sia accesa adesso. Con questa attiva la mappa passa a notturna
--- alle 22 e torna chiara alle 6, e in mezzo l'interruttore resta a
--- disposizione - chi lo preme decide per quella notte, e il cambio d'ora
--- successivo riprende in mano il comando.
function NW.darkAuto()
    return readPrefs().dark_auto == "1"
end

function NW.setDarkAuto(on)
    readPrefs().dark_auto = on and "1" or "0"
    writePrefs()
    return on
end

--- La nuova misura, scritta subito: la maniglia si molla una volta sola e non
--- c'e' un momento migliore per salvare.
function NW.setPanelScale(s)
    s = clampScale(s)
    if scale and math.abs(s - scale) < 0.0005 then return s end
    scale = s
    readPrefs().panel_scale = string.format("%.4f", s)
    writePrefs()
    return s
end

-- ---------------------------------------------------------------------------
-- La larghezza del pannello, che non e' piu' la sua scala
-- ---------------------------------------------------------------------------
--
-- PRIMA ERANO UN NUMERO SOLO. La maniglia tirava la scala, e la larghezza era
-- `larghezza di progetto * scala`: ingrandire le lettere per leggerle meglio a
-- 4K voleva dire allargare il pannello nella stessa proporzione, e a scala 2 il
-- pannello si mangiava mezza mappa. La segnalazione chiedeva di farlo "come
-- l'inventario": li' le righe crescono con il carattere, ma quanto e' larga la
-- finestra lo decide chi la tira.
--
-- Adesso sono due. La scala dice quanto sono grandi le cose dentro; il
-- fattore di larghezza dice quanto e' largo il pannello, sempre in multipli
-- della larghezza di progetto. Il pannello non scende mai sotto quanto serve
-- alla sua riga di tasti piu' larga - quello lo decide NW_Panel, che le misura.
--
-- Chi aggiorna dalla versione di prima non ha il secondo numero: parte dalla
-- sua scala, cioe' esattamente dal pannello che aveva. Stringerlo e' un gesto
-- suo, non una sorpresa dell'aggiornamento.
local widthF = nil

local function clampWidthF(f)
    f = tonumber(f) or NW.SCALE.DEFAULT
    return math.max(0.5, math.min(NW.SCALE.MAX, f))
end

function NW.panelWidthFactor()
    if not widthF then
        widthF = clampWidthF(readPrefs().panel_widthf or NW.panelScale())
    end
    return widthF
end

function NW.setPanelWidthFactor(f)
    f = clampWidthF(f)
    if widthF and math.abs(f - widthF) < 0.0005 then return f end
    widthF = f
    readPrefs().panel_widthf = string.format("%.4f", f)
    writePrefs()
    return f
end

--- La larghezza vera di un pannello nato con questa larghezza di progetto.
--- Serve a chi deve lasciargli il posto - la pagina, la mappa di carta -
--- prima ancora che il pannello esista. E' una stima buona, non la misura: il
--- pannello puo' dover crescere per la sua riga di tasti, e allora chi lo ospita
--- si rimette a posto quando il pannello glielo dice (onResized).
function NW.panelWidth(base, s, f)
    s = s or NW.panelScale()
    f = f or NW.panelWidthFactor()
    local w = math.max((base or NW.PANEL_W) * f, NW.PANEL_MIN_W * s)
    return math.floor(math.min(w, getCore():getScreenWidth() * 0.5))
end

-- ---------------------------------------------------------------------------
-- Preferenze semplici
-- ---------------------------------------------------------------------------
--
-- Le voci che seguono sono tutte uguali - un si' o no, oppure un numero - e
-- stanno nello stesso file per la stessa ragione della misura: sono preferenze
-- di chi guarda, non fatti del personaggio.

local function prefBool(key, default)
    local v = readPrefs()[key]
    if v == nil then return default end
    return v == "1"
end

local function setPrefBool(key, on)
    readPrefs()[key] = on and "1" or "0"
    writePrefs()
    return on
end

local function prefNumber(key, default, lo, hi)
    local v = tonumber(readPrefs()[key])
    if not v then return default end
    return math.max(lo, math.min(hi, v))
end

local function setPrefNumber(key, v)
    readPrefs()[key] = string.format("%.4f", v)
    writePrefs()
    return v
end

--- La mappa del mondo segue il personaggio mentre cammina.
function NW.mapFollow() return prefBool("map_follow", false) end
function NW.setMapFollow(on) return setPrefBool("map_follow", on) end

--- Biglietti e simboli si stendono sulla mappa quando la vista e' isometrica.
---
--- ACCESO DI PARTENZA, perche' e' quello che la segnalazione chiedeva che
--- succedesse da solo; chi li vuole in piedi come in vanilla lo spegne dal tasto
--- della prospettiva nel pannello.
function NW.marksFollowPerspective() return prefBool("marks_iso", true) end
function NW.setMarksFollowPerspective(on) return setPrefBool("marks_iso", on) end

--- L'ultima misura scelta per un simbolo o per un biglietto, come multiplo della
--- misura di partenza (1 = come nasce in vanilla).
---
--- QUATTRO NUMERI, NON DUE. La mappa e il foglio si ricordano ognuno la sua:
--- un simbolo ingrandito sulla mappa del mondo, guardata da lontano, non deve
--- far nascere enormi i simboli del diario.
local SIZE_KEYS = {
    map  = { sym = "size_map_sym",  note = "size_map_note" },
    page = { sym = "size_page_sym", note = "size_page_note" },
}

function NW.lastSize(where, kind)
    local k = SIZE_KEYS[where] and SIZE_KEYS[where][kind]
    if not k then return 1 end
    return prefNumber(k, 1, 0.1, 20)
end

function NW.setLastSize(where, kind, ratio)
    local k = SIZE_KEYS[where] and SIZE_KEYS[where][kind]
    if not (k and ratio and ratio > 0) then return end
    return setPrefNumber(k, math.max(0.1, math.min(20, ratio)))
end

function NW.inkById(id)
    for _, ink in ipairs(NW.INKS) do
        if ink.id == id then return ink end
    end
    return NW.INKS[1]
end

-- ---------------------------------------------------------------------------
-- Simboli posati sulla carta
-- ---------------------------------------------------------------------------
-- Quanto grande nasce un simbolo posato su una pagina, in pixel di schermo.
-- Da li' in poi lo si ridimensiona con il tasto Modifica, come sulla mappa.
NW.SYMBOL_SIZE = 44

--- La texture di un simbolo, dal suo id.
---
--- MapSymbolDefinitions e' l'unico registro che li conosce tutti - i nostri, i
--- suoi e quelli di chiunque altro - ma sa rispondere solo per indice, quindi
--- la corrispondenza si costruisce una volta e si tiene. Non si invalida: i
--- simboli si registrano al caricamento e da li' non cambiano piu'. Quello che
--- cambia sono i PACCHETTI ACCESI, che decidono cosa si puo' scegliere, non
--- cosa si puo' disegnare: un simbolo gia' posato su una pagina deve restare
--- visibile anche dopo che il giocatore ha spento il suo pacchetto.
local symTex = nil

function NW.symbolTexture(id)
    if not id then return nil end
    if not symTex then
        symTex = {}
        local defs = MapSymbolDefinitions.getInstance()
        local ok, count = pcall(function() return defs:getSymbolCount() end)
        if ok and count then
            for i = 0, count - 1 do
                local sym = defs:getSymbolByIndex(i)
                local sid = sym and sym:getId()
                local path = sym and sym:getTexturePath()
                if sid and path then symTex[sid] = getTexture(path) end
            end
        end
    end
    return symTex[id]
end
