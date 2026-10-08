--[[ ============================================================================
    NW_ModOptions - Options > Mods > "Project Writing".

    Only preferences live here. Anything the player changes by using the panel -
    which tool is armed, which pen, how thick the stroke - is UI state and dies
    with the map screen. The size of the panel is neither: it is set by dragging
    its corner and kept in ProjectWriting.ini (NW_Config), because a control you
    reach by using the thing is better than one you reach through a menu.

    Two switches change behaviour rather than looks, and both came from players
    running servers: the world does not have to stop while you write, and the
    map can be left to the game entirely.

    Three symbol packs, three tickboxes. The game's own and the hand-drawn set
    are on; the 95-tile set is off, because a sheet nobody asked to grow should
    not grow. All three are registered either way - the switch is on the sheet,
    so a symbol already drawn on a saved map keeps its texture whatever is
    ticked here.

    Every label goes through tr() rather than getText: this file runs while the
    game is still loading, before the translation tables are guaranteed to be
    there, and getText hands back the raw key when it cannot answer. An options
    screen reading "UI_NW_options_pack_extra" is worse than one in English.

    Mod Options is a separate mod's API. Without it the mod still works with its
    defaults; only the preference screen goes away.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Categories"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Focus"
require "ISUI/Maps/ISWorldMap"
require "NeatWriting/Patches/NW_Map"

if not PZAPI or not PZAPI.ModOptions then return end

local function tr(key, fallback)
    if not getText then return fallback end
    local t = getText(key)
    if not t or t == key then return fallback end
    return t
end

-- La chiave sotto cui PZAPI salva le impostazioni. E' l'id della mod, come in
-- Hairstyler e XP Drop. Era rimasta "NEATUI_WRITING" dal vecchio nome: si
-- cambia adesso perche' la mod non e' mai uscita e nessuno ha impostazioni
-- salvate li' sotto. Dopo la prima pubblicazione cambiarla le azzererebbe.
local MOD_ID = "ProjectWriting"

local options = PZAPI.ModOptions:create(MOD_ID, tr("UI_NW_options_title", "Project Writing"))

-- addTitle vuole la chiave, non il testo: la traduce da se' (come Hairstyler).
options:addTitle("UI_NW_options_writing")

options:addTickBox("PAUSE",
    tr("UI_NW_options_pause", "Pause the game while writing"), true,
    tr("UI_NW_options_pause_tooltip",
       "The world stops while a sheet or a paper map is open. Turn it off to keep the game running - on a server, or to write with the world still moving around you."))

-- Il tetto di battute per facciata. Serve dove la stessa pagina la leggono
-- schermi diversi: su un server di gioco di ruolo lo impone l'opzione sandbox,
-- che qui vince (NW.pageCharLimit). La prima voce e' "nessuno".
local PAGE_LIMITS = { 0, 300, 500, 800, 1200 }
local limitCombo = options:addComboBox("PAGE_LIMIT",
    tr("UI_NW_options_page_limit", "Characters per page"),
    tr("UI_NW_options_page_limit_tooltip",
       "The most you can write on one page. A counter appears under the text while you write. On a server the sandbox setting decides for everyone."))
limitCombo:addItem("UI_NW_options_page_limit_none", true)
for i = 2, #PAGE_LIMITS do limitCombo:addItem(tostring(PAGE_LIMITS[i]), false) end

options:addTitle("UI_NW_options_map")

-- Spento di partenza: la mappa vestita da noi e' meta' della mod.
--
-- Chi lo accende ha una ragione precisa, e viene da un server: la mappa di
-- vanilla e le sue funzioni di condivisione sono l'ossatura di certe partite
-- in rete, e chi ci gioca vuole il resto della mod senza rischiare quelle. Non
-- e' un ripiego per un difetto nostro, e' una scelta che va lasciata.
options:addTickBox("VANILLA_MAP",
    tr("UI_NW_options_vanilla_map", "Leave the map to the game"), false,
    tr("UI_NW_options_vanilla_map_tooltip",
       "The world map and paper maps open with the game's own panels, buttons and sharing, exactly as if this mod were not installed. The bundled symbol packs stay. Writing on paper is not affected. For servers built around the vanilla map."))

-- Il mondo che continua ad andare con la mappa del mondo aperta.
--
-- Vanilla ha un'opzione sua per questo, fra quelle del gioco, lontana da dove
-- serve. Questa sta con la mappa, e accesa vince lei; spenta decide quella di
-- vanilla, come prima. E' la compagna naturale della vista che segue il
-- personaggio (NW_Follow): seguire uno che non cammina non serve a niente.
-- In rete non cambia nulla, perche' in rete la mappa non ferma mai il mondo.
options:addTickBox("MAP_NOPAUSE",
    tr("UI_NW_options_map_nopause", "Keep the world running on the world map"), false,
    tr("UI_NW_options_map_nopause_tooltip",
       "Opening the world map does not pause the game in single player, so your character can keep walking while you read the map. Off, the game's own option decides, as before."))

-- Ctrl/Shift + rotella mentre si posa un simbolo o si scrive un biglietto.
options:addTickBox("PLACE_ADJUST",
    tr("UI_NW_options_place_adjust", "Size and angle while placing"), true,
    tr("UI_NW_options_place_adjust_tooltip",
       "While you hold a symbol or write a note on the map, Ctrl + mouse wheel changes its size and Shift + mouse wheel turns it, before it is placed. The wheel alone still zooms the map."))

options:addTitle("UI_NW_options_sharing")

-- Spartire le note, o tenersele.
--
-- Spegnerlo non e' come mettere "solo io" nel pannello: quella e' una scelta
-- che si cambia di continuo, questa toglie di mezzo la funzione - il tasto con
-- l'aeroplanino sparisce e non parte piu' niente per il server. Per chi la mod
-- la vuole solo per scrivere, e per chi in rete preferisce che le sue
-- annotazioni restino sue senza doverci pensare ogni volta.
options:addTickBox("SHARE",
    tr("UI_NW_options_share", "Share notes with other players"), true,
    tr("UI_NW_options_share_tooltip",
       "In multiplayer, lets you choose who each new symbol, note and stroke is written for - your faction, your safehouse, chosen players, everyone. Turn it off and the sharing button disappears: nothing you write leaves your own map. Single player is not affected."))

options:addTitle("UI_NW_options_packs")

options:addTickBox("PACK_VANILLA",
    tr("UI_NW_options_pack_vanilla", "The game's own symbols"), true,
    tr("UI_NW_options_pack_vanilla_tooltip",
       "The 91 symbols Project Zomboid ships with."))

options:addTickBox("PACK_EXTRA",
    tr("UI_NW_options_pack_extra", "Hand-drawn set"), true,
    tr("UI_NW_options_pack_extra_tooltip",
       "46 hand-drawn symbols bundled with this mod, from ExtraMapSymbols."))

-- Spento, a meno che il giocatore non abbia installato Add More Map Symbols per
-- conto suo: in quel caso quei simboli li vuole gia'.
options:addTickBox("PACK_AMMS",
    tr("UI_NW_options_pack_amms", "Extended set"), NW_Categories.ammsModInstalled(),
    tr("UI_NW_options_pack_amms_tooltip",
       "95 more symbols bundled with this mod, from Add More Map Symbols: vehicles, tools, weapons and furniture. Off by default because it triples the size of the sheet."))

--- La mappa del mondo si costruisce UNA VOLTA per partita e poi si riusa, quindi
--- cambiare "lascia la mappa al gioco" non basta a cambiarla: la si butta e la
--- prossima apertura la rifa' leggendo l'opzione nuova (NW_Map.dropWorldMap, che
--- serve anche all'opzione sandbox). Il prezzo e' la vista corrente, che si
--- riapre centrata sul personaggio: e' un prezzo giusto per un tasto che
--- altrimenti mentirebbe fino al riavvio.
local function dropWorldMap()
    NW_Map.dropWorldMap()
end

function options:apply()
    -- La regola in vigore, non la spunta: con la sandbox che impone la mappa di
    -- vanilla la spunta personale non cambia niente, e non c'e' niente da buttare.
    local wasVanillaMap = NW.vanillaMap()
    local wasPacks = NW.packSignature()

    NW.prefs.pause      = self:getOption("PAUSE"):getValue() ~= false
    NW.prefs.vanillaMap = self:getOption("VANILLA_MAP"):getValue() == true
    NW.prefs.share      = self:getOption("SHARE"):getValue() ~= false
    NW.prefs.mapNoPause = self:getOption("MAP_NOPAUSE"):getValue() == true
    NW.prefs.placeAdjust = self:getOption("PLACE_ADJUST"):getValue() ~= false
    NW.prefs.pageLimit = PAGE_LIMITS[tonumber(self:getOption("PAGE_LIMIT"):getValue()) or 1] or 0

    -- Un mondo lasciato fermo da una finestra chiusa non riparte da solo: se la
    -- pausa si spegne mentre una pagina e' aperta, la si restituisce adesso.
    if not NW.prefs.pause and NW_Focus and NW_Focus.thaw then NW_Focus.thaw() end

    NW.packs[NW_Categories.PACK_VANILLA] = self:getOption("PACK_VANILLA"):getValue() ~= false
    NW.packs[NW_Categories.PACK_EXTRA]   = self:getOption("PACK_EXTRA"):getValue() ~= false
    NW.packs[NW_Categories.PACK_AMMS]    = self:getOption("PACK_AMMS"):getValue() == true

    -- Straight through to any sheet that is already up. This runs off the OK
    -- button, not off a render pass, so rebuilding the sheet here is safe -
    -- and it is the difference between the switch working now and working the
    -- next time the panel happens to be reopened.
    local picker = rawget(_G, "NW_SymbolPicker")
    if picker and picker.refreshAll then pcall(picker.refreshAll) end

    -- La mappa del mondo si butta in due casi, e per la stessa ragione: quello
    -- che c'e' dentro e' stato costruito una volta e non si rifa' da solo.
    --
    --   * l'opzione della mappa e' cambiata: cambia tutto il vestito;
    --   * un pacchetto e' cambiato CON la mappa lasciata al gioco: li' i
    --     simboli li elenca il pannello di vanilla, che la sua lista se l'e'
    --     costruita all'apertura. La nostra tavola si rifa' da se' (sopra), la
    --     sua no - ed e' esattamente il "sembra non risentire delle opzioni
    --     dei pacchetti" della segnalazione.
    if NW.vanillaMap() ~= wasVanillaMap
        or (NW.vanillaMap() and NW.packSignature() ~= wasPacks) then
        dropWorldMap()
    end
end

-- PZAPI applies the saved values when the options screen is confirmed, but not
-- reliably at load: without this the first session runs on the defaults no
-- matter what is in ModOptions.ini. Idempotent, so calling it again costs
-- nothing.
Events.OnGameStart.Add(function()
    pcall(function() options:apply() end)
end)

return options
