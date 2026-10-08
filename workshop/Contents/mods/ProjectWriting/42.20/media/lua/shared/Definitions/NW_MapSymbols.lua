--[[ ============================================================================
    NW_MapSymbols - i simboli che questa mod aggiunge alla mappa.

    Due pacchetti, entrambi inclusi qui dentro perche' la mod non abbia bisogno
    di nessun'altra:

      nw:*    46 disegni da ExtraMapSymbols (Wipe, Lexx, B - Rotators)
      AmmS*   95 disegni da Add More Map Symbols (Golem)

    Gli autori vanno citati sulla pagina Workshop.

    Del primo pacchetto si usa la cartella corrente e non le copie "nostalgia":
    quelle sono disegnate piene, e una forma piena a dimensione mappa diventa una
    macchia nera - e' esattamente come veniva il vecchio "heart", che infatti non
    c'e'. Fuori anche le varianti numerate (dot.0, x_small.1...): sono misure
    diverse di un simbolo gia' presente, e cinque tessere quasi uguali rendono la
    tavola piu' difficile da leggere, non piu' ricca.

    Il secondo pacchetto tiene gli id di Add More Map Symbols invece di
    prendersene di nostri, e viene registrato solo se quella mod non e' attiva.
    Cosi gli id sono gli stessi in tutti e due i casi - i nomi, le categorie e i
    simboli gia' disegnati su una mappa salvata continuano a funzionare - e non
    si registra mai due volte lo stesso.

    Le schede si leggono da NW_Categories, non da qui: la tavola non chiede a
    MapSymbolDefinitions dove va un simbolo. Il terzo argomento e' sempre una
    delle tre schede del gioco, e deve restare tale - una nostra categoria li'
    dentro fa crashare il pannello simboli del gioco, che noi nascondiamo ma che
    il gioco costruisce lo stesso. Il perche' e' in NW_Categories.VANILLA_TAB.
============================================================================ ]]--

-- Definitions load early and in their own pass. If the taxonomy is not reachable
-- yet the symbols still have to register: the tab written here is only for
-- whoever else reads it, since the sheet asks NW_Categories directly.
pcall(require, "NeatWriting/NW_Categories")

--- Sempre una delle tre schede del gioco, mai una delle nostre nove: il
--- pannello simboli del gioco crasha su una scheda che sta su una riga sola, e
--- una nostra categoria magra ci sta. Il perche' per esteso e' in
--- NW_Categories.VANILLA_TAB.
local function tabFor(id)
    local C = rawget(_G, "NW_Categories")
    return (C and C.vanillaTabOf(id)) or "Symbols"
end

local defs = MapSymbolDefinitions.getInstance()

-- --------------------------------------------------------------------------
-- ExtraMapSymbols
-- --------------------------------------------------------------------------

local EXTRA_PATH = "media/ui/NeatWriting/Symbols/"
local EXTRA = {
    "ammo", "arrow1", "arrow2", "arrow3", "arrow4", "axe", "axe2", "bed",
    "boat", "book", "car", "cross", "dot", "electricity", "fire", "food",
    "fuel", "fuel2", "helicopter", "helmet", "important", "line1", "line2",
    "line3", "line4", "loot", "marine", "medic", "meet", "parachute", "pills",
    "pipeWrench", "pistol", "radioactive", "school", "sheriff", "shirt",
    "sledge", "tent", "trashpanda", "truck", "vhs", "warehouse", "water",
    "wrench", "x_small",
}

for _, name in ipairs(EXTRA) do
    local id = "nw:" .. name
    defs:addTexture(id, EXTRA_PATH .. name .. ".png", tabFor(id))
end

-- --------------------------------------------------------------------------
-- Add More Map Symbols
-- --------------------------------------------------------------------------

--- Se la mod vera e' accesa, i suoi 95 li mette lei. La domanda la fa
--- NW_Categories, perche' le opzioni la fanno alla stessa tabella.
local function ammsInstalled()
    local C = rawget(_G, "NW_Categories")
    if C then return C.ammsModInstalled() end
    -- Se la tabella non e' arrivata la domanda va fatta comunque: registrare i
    -- 95 mentre li registra anche lui vorrebbe dire ogni tessera due volte.
    local ok, mods = pcall(getActivatedMods)
    return ok and mods ~= nil and mods:contains("AMMS_Standalone")
end

if not ammsInstalled() then
    local AMMS_PATH = "media/ui/NeatWriting/SymbolsAMMS/"
    -- famiglia -> quante ne ha. Gli id sono AmmS<famiglia>_<n>, dall'1.
    local AMMS = {
        { "Sign", 14 }, { "Car", 15 }, { "Weapon", 13 },
        { "Tool", 28 }, { "Furniture", 25 },
    }
    for _, family in ipairs(AMMS) do
        for n = 1, family[2] do
            local id = "AmmS" .. family[1] .. "_" .. n
            defs:addTexture(id, AMMS_PATH .. id .. ".png", tabFor(id))
        end
    end
end
