--[[ ============================================================================
    NW_Categories - dove va ogni simbolo nella tavola.

    Ogni pacchetto arriva con la sua idea di scheda, e le tre idee non parlano
    fra loro: il gioco archivia in Locations/Loot/Symbols, AddMoreMapSymbols in
    AmmSSign/AmmSToolGuns/AmmSFurniture (con le auto sotto i cartelli), e i
    nostri stavano dove li avevamo messi noi. Il risultato erano nove schede che
    dicevano da quale mod veniva un simbolo, non che cosa fosse.

    Qui c'e' una tassonomia sola per tutti e 232. La scheda si legge da questa
    tabella, non da sym:getTab(), quindi non serve ri-registrare niente: i
    simboli del gioco restano quelli del gioco e cambia solo dove compaiono.

    Un simbolo di una mod che non conosciamo non e' qui dentro: tiene la sua
    scheda dichiarata, cosi non lo perdiamo di vista.
============================================================================ ]]--

NW_Categories = NW_Categories or {}
local C = NW_Categories

-- Gli id delle schede. Sono nostri, quindi non possono scontrarsi con quelli
-- di nessuno.
C.MARKS   = "NW_Marks"
C.PLACES  = "NW_Places"
C.LOOT    = "NW_Loot"
C.ROAD    = "NW_Road"
C.TOOLS   = "NW_Tools"
C.WEAPONS = "NW_Weapons"
C.HAZARD  = "NW_Hazard"
C.ANIMALS = "NW_Animals"
C.HOME    = "NW_Home"

--- L'ordine in cui si leggono. I segni per primi: freccia, croce e X sono
--- quello che si mette piu' spesso e piu' in fretta.
C.ORDER = {
    C.MARKS, C.PLACES, C.LOOT, C.ROAD,
    C.TOOLS, C.WEAPONS, C.HAZARD, C.ANIMALS, C.HOME,
}

--- Scheda -> chiave di traduzione del suo nome.
C.LABELS = {
    [C.MARKS]   = "IGUI_NW_TabMarks",
    [C.PLACES]  = "IGUI_NW_TabPlaces",
    [C.LOOT]    = "IGUI_NW_TabLoot",
    [C.ROAD]    = "IGUI_NW_TabRoad",
    [C.TOOLS]   = "IGUI_NW_TabTools",
    [C.WEAPONS] = "IGUI_NW_TabWeapons",
    [C.HAZARD]  = "IGUI_NW_TabHazard",
    [C.ANIMALS] = "IGUI_NW_TabAnimals",
    [C.HOME]    = "IGUI_NW_TabHome",
}

--- La scheda del gioco con cui registrare un simbolo di una nostra categoria.
---
--- Le nostre nove schede vivono solo nella nostra tavola. A MapSymbolDefinitions
--- si dichiara sempre una delle tre del gioco, e non e' pignoleria:
--- ISWorldMapSymbols - il pannello del gioco, che noi nascondiamo ma che il gioco
--- costruisce lo stesso a ogni apertura della mappa - dispone le tessere su
--- otto colonne e poi fa
---
---     tab.joypadIndexY = math.floor(#tab.joypadButtonsY / 2)
---     tab.joypadButtons = tab.joypadButtonsY[tab.joypadIndexY]
---     tab.joypadIndex = math.ceil(#tab.joypadButtons / 2)
---
--- Una scheda con otto tessere o meno sta su una riga sola: floor(1/2) e' 0,
--- joypadButtonsY[0] e' nil, e #nil e' "__len not defined for operand". Aprire
--- la mappa crashava per questo, perche' con i simboli del gioco che restano
--- nelle schede loro la nostra "Animali" conteneva un procione e basta.
---
--- Registrando nelle tre del gioco quel caso non puo' presentarsi: sono schede
--- da decine di tessere. La nostra tavola non guarda comunque questo valore -
--- chiede a C.tabOf.
C.VANILLA_TAB = {}

--- Sotto quante tessere una scheda non vale piu' la pena di esistere.
C.MIN_TILES = 3

--- Dove finisce una scheda rimasta troppo magra.
---
--- I pacchetti si accendono e si spengono, e con tre interruttori le
--- combinazioni sono otto: col solo pacchetto disegnato a mano gli animali sono
--- un procione e i mobili un letto, e una scheda con dentro una tessera e' una
--- scheda sprecata. Invece di limare a mano gli otto casi, ogni scheda dice
--- dove versarsi quando resta vuota; la tavola si adatta da sola a qualunque
--- combinazione, anche a quelle che nascono da una mod di simboli futura.
---
--- I segni non hanno un dove: sono il fondo in cui tutto il resto finisce.
C.FALLBACK = {
    [C.ANIMALS] = C.LOOT,      -- selvaggina e bestiame: roba da prendere
    [C.HOME]    = C.LOOT,
    [C.TOOLS]   = C.LOOT,
    [C.WEAPONS] = C.LOOT,
    [C.ROAD]    = C.PLACES,    -- un veicolo e' comunque un posto dove andare
    [C.HAZARD]  = C.MARKS,     -- un avvertimento e' un segno
    [C.PLACES]  = C.MARKS,
    [C.LOOT]    = C.MARKS,
}

local M, P, L, R, T, W, H, A, F =
    C.MARKS, C.PLACES, C.LOOT, C.ROAD,
    C.TOOLS, C.WEAPONS, C.HAZARD, C.ANIMALS, C.HOME

C.VANILLA_TAB[M] = "Symbols"
C.VANILLA_TAB[H] = "Symbols"
C.VANILLA_TAB[P] = "Locations"
C.VANILLA_TAB[R] = "Locations"
C.VANILLA_TAB[L] = "Loot"
C.VANILLA_TAB[T] = "Loot"
C.VANILLA_TAB[W] = "Loot"
C.VANILLA_TAB[A] = "Loot"
C.VANILLA_TAB[F] = "Loot"

--- Con quale scheda del gioco registrare un simbolo. Mai una nostra.
function C.vanillaTabOf(id)
    return C.VANILLA_TAB[C.OF[id]] or "Symbols"
end

--- id del simbolo -> scheda.
C.OF = {
    -- ---- i 91 del gioco -------------------------------------------------
    ArrowEast = M, ArrowNorth = M, ArrowSouth = M, ArrowWest = M,
    ArrowNorthWest = M, ArrowNorthEast = M, ArrowSouthWest = M, ArrowSouthEast = M,
    Asterisk = M, Checkmark = M, Club = M, Diamond = M, Heart = M, Spade = M,
    Cross = M, Exclamation = M, Question = M, Circle = M, Triangle = M, Star = M,
    FaceDead = M, FaceHappy = M, FaceSad = M, Heartbroken = M, X = M,
    Moon = M, Sun = M, Snowflake = M, Leaf = M, Flower = M, Tree = M, Eye = M,
    Target = M,

    House = P, Skyscraper = P, KnifeFork = P, MedCross = P, Police = P,
    Lock = P, Key = P, Door = P, Ladder = P, Columns = P, Tent = P,

    Apple = L, Burger = L, Fish = L, Egg = L, Garbage = L, DollarSign = L,
    Pill = L, Shirt = L, Book = L, VHS = L, Lightbulb = L, Waves = L,
    Baseball = L,

    Boat = R, Tire = R, SteeringWheel = R, Fuel = R,

    Axe = T, Wrench = T, Hammer = T, Gears = T,

    Gun = W, Knife = W, CrossedSwords = W, Bullets = W, Bomb = W, Armor = W,

    Fire = H, Lightning = H, Radiation = H, Skull = H, Trap = H, Z = H,

    Sheep = A, Rabbit = A, Cow = A, Deer = A, Pig = A, Chicken = A,
    Rodent = A, Raccoon = A, Turkey = A, Bird = A, Pawprint = A,

    Furnace = F, Bed = F, Anvil = F,

    -- ---- i nostri 46 ----------------------------------------------------
    ["nw:arrow1"] = M, ["nw:arrow2"] = M, ["nw:arrow3"] = M, ["nw:arrow4"] = M,
    ["nw:line1"] = M, ["nw:line2"] = M, ["nw:line3"] = M, ["nw:line4"] = M,
    ["nw:cross"] = M, ["nw:dot"] = M, ["nw:important"] = M,
    ["nw:x_small"] = M, ["nw:fuel2"] = M,

    ["nw:axe2"] = P, ["nw:school"] = P, ["nw:sheriff"] = P, ["nw:warehouse"] = P,
    ["nw:marine"] = P, ["nw:meet"] = P, ["nw:parachute"] = P, ["nw:tent"] = P,
    ["nw:electricity"] = P,

    ["nw:ammo"] = W, ["nw:helmet"] = W, ["nw:pistol"] = W,

    ["nw:book"] = L, ["nw:food"] = L, ["nw:loot"] = L, ["nw:medic"] = L,
    ["nw:pills"] = L, ["nw:shirt"] = L, ["nw:vhs"] = L, ["nw:water"] = L,

    ["nw:boat"] = R, ["nw:car"] = R, ["nw:fuel"] = R, ["nw:helicopter"] = R,
    ["nw:truck"] = R,

    ["nw:axe"] = T, ["nw:pipeWrench"] = T, ["nw:sledge"] = T, ["nw:wrench"] = T,

    ["nw:fire"] = H, ["nw:radioactive"] = H,

    ["nw:trashpanda"] = A,

    ["nw:bed"] = F,

    -- ---- i 95 di AddMoreMapSymbols --------------------------------------
    AmmSSign_1 = R, AmmSSign_2 = R, AmmSSign_9 = R,
    AmmSSign_3 = H, AmmSSign_5 = H, AmmSSign_6 = H, AmmSSign_7 = H,
    AmmSSign_8 = H, AmmSSign_12 = H, AmmSSign_13 = H,
    AmmSSign_4 = P, AmmSSign_10 = P, AmmSSign_11 = P, AmmSSign_14 = P,

    AmmSCar_1 = R, AmmSCar_2 = R, AmmSCar_3 = R, AmmSCar_4 = R, AmmSCar_5 = R,
    AmmSCar_6 = R, AmmSCar_7 = R, AmmSCar_8 = R, AmmSCar_9 = R, AmmSCar_10 = R,
    AmmSCar_11 = R, AmmSCar_12 = R, AmmSCar_13 = R, AmmSCar_14 = R, AmmSCar_15 = R,

    AmmSWeapon_1 = W, AmmSWeapon_2 = W, AmmSWeapon_3 = W, AmmSWeapon_4 = W,
    AmmSWeapon_5 = W, AmmSWeapon_6 = W, AmmSWeapon_7 = W, AmmSWeapon_8 = W,
    AmmSWeapon_9 = W, AmmSWeapon_10 = W, AmmSWeapon_11 = W, AmmSWeapon_12 = W,
    AmmSWeapon_13 = W,

    AmmSTool_1 = L, AmmSTool_2 = L, AmmSTool_3 = L, AmmSTool_4 = L, AmmSTool_6 = L,
    AmmSTool_5 = T, AmmSTool_7 = T, AmmSTool_8 = T, AmmSTool_9 = T,
    AmmSTool_10 = T, AmmSTool_11 = T, AmmSTool_12 = T, AmmSTool_13 = T,
    AmmSTool_14 = T, AmmSTool_15 = T, AmmSTool_16 = T, AmmSTool_17 = T,
    AmmSTool_18 = T, AmmSTool_23 = T, AmmSTool_24 = T, AmmSTool_25 = T,
    AmmSTool_26 = T, AmmSTool_27 = T, AmmSTool_28 = T,
    AmmSTool_19 = F,
    AmmSTool_20 = R, AmmSTool_21 = R, AmmSTool_22 = R,

    AmmSFurniture_1 = F, AmmSFurniture_2 = F, AmmSFurniture_3 = F,
    AmmSFurniture_4 = F, AmmSFurniture_5 = F, AmmSFurniture_6 = F,
    AmmSFurniture_7 = F, AmmSFurniture_8 = F, AmmSFurniture_9 = F,
    AmmSFurniture_10 = F, AmmSFurniture_11 = F, AmmSFurniture_12 = F,
    AmmSFurniture_13 = F, AmmSFurniture_14 = F, AmmSFurniture_15 = F,
    AmmSFurniture_16 = F, AmmSFurniture_17 = F, AmmSFurniture_18 = F,
    AmmSFurniture_20 = F,
    AmmSFurniture_19 = L, AmmSFurniture_23 = L, AmmSFurniture_24 = L,
    AmmSFurniture_25 = L,
    AmmSFurniture_21 = P, AmmSFurniture_22 = P,
}

--- Dove sta un simbolo, o nil se non lo sappiamo.
function C.tabOf(id)
    return C.OF[id]
end

-- ---------------------------------------------------------------------------
-- Pacchetti
-- ---------------------------------------------------------------------------

C.PACK_VANILLA = "vanilla"
C.PACK_EXTRA   = "extra"     -- i 46 nostri, da ExtraMapSymbols
C.PACK_AMMS    = "amms"      -- i 95 in stile AddMoreMapSymbols

--- Se Add More Map Symbols e' acceso per conto suo.
---
--- Serve in due posti che devono dire la stessa cosa: le definizioni, che non
--- registrano i 95 se ci ha gia' pensato lui, e le opzioni, dove quel pacchetto
--- parte acceso se il giocatore quella mod l'ha voluta installare.
function C.ammsModInstalled()
    local ok, mods = pcall(getActivatedMods)
    if not ok or not mods then return false end
    return mods:contains("AMMS_Standalone") or mods:contains("\\AMMS_Standalone")
end

--- Da quale pacchetto viene un simbolo, o nil se da nessuno dei tre.
---
--- Il prefisso dell'id basta per i due pacchetti aggiunti. Per quelli del gioco
--- si guarda invece la texture: "media/ui/LootableMaps/map_*" e' come li chiama
--- il gioco da sempre, e cosi un simbolo aggiunto in una build futura ricade
--- da solo nel posto giusto senza che dobbiamo elencarlo.
---
--- nil vuol dire "di qualcun altro": quelli si vedono sempre, non e' roba
--- nostra da accendere e spegnere.
function C.packOf(id, texturePath)
    id = tostring(id or "")
    if id:sub(1, 3) == "nw:" then return C.PACK_EXTRA end
    if id:sub(1, 4) == "AmmS" then return C.PACK_AMMS end
    if texturePath and texturePath:find("media/ui/LootableMaps/map_", 1, true) == 1 then
        return C.PACK_VANILLA
    end
    return nil
end

--- Versa le schede rimaste magre in quelle che le raccolgono.
---
--- `groups` e' scheda -> lista di tessere, e viene modificata sul posto.
---
--- Si scorre C.ORDER al contrario perche' le schede che raccolgono stanno in
--- cima: cosi Mobili finisce in Bottino prima che tocchi a Bottino decidere se
--- e' magro a sua volta, e una tavola quasi vuota collassa fino ai Segni in una
--- passata sola invece di lasciare in giro schede da una tessera.
---
--- Le schede di mod che non conosciamo non si toccano: non sappiamo cosa
--- contengono e non e' roba nostra da spostare.
function C.foldThin(groups)
    for i = #C.ORDER, 1, -1 do
        local tab = C.ORDER[i]
        local list = groups[tab]
        local into = C.FALLBACK[tab]
        if list and into and #list < C.MIN_TILES then
            groups[into] = groups[into] or {}
            local dest = groups[into]
            for _, entry in ipairs(list) do dest[#dest + 1] = entry end
            groups[tab] = nil
        end
    end
    return groups
end

--- Quanto in basso sta una scheda. Le nostre nell'ordine deciso, tutto il
--- resto - le schede di mod che non conosciamo - dopo, in ordine alfabetico.
function C.rank(tab)
    for i, name in ipairs(C.ORDER) do
        if name == tab then return i end
    end
    return #C.ORDER + 1
end

return NW_Categories
