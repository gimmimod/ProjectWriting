--[[ ============================================================================
    NW_MapButtons - the world map's own button bar, in the family's clothes.

    Vanilla builds a row of plain ISButtons, three of which are bare letters
    ("C", "S", "P", "?") sitting next to icon buttons. Rather than rebuild the
    bar - and inherit the job of keeping it in sync with future builds - each
    button is restyled in place: the same objects, the same callbacks, our
    painter and our icons.

    Two of them go away entirely:
      S       toggled vanilla's symbol panel, which we replace; pressing it
              flashed the old panel back for a second.
      CHIUDI  the Writing panel's red X closes the map, and M still works, so a
              third way to do it is one too many.
============================================================================ ]]--

if isServer() then return end

require "ISUI/Maps/ISWorldMap"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Style"
require "NeatWriting/UI/NW_Tooltip"
require "NeatWriting/NW_Follow"

local ICONS = NW.ICONS

--- La misura di un tasto della fila, e l'aria fra uno e l'altro. Vanilla li fa
--- 48 (la larghezza di ViewIsometric.png) e li mette a 10 di distanza.
local BTN_SIZE = 58
local BTN_GAP  = 6

--- Quanto dell'altezza del tasto prende l'icona dentro.
local ICON_FILL = 0.72

--- The picture each vanilla button should carry. Anything not named here keeps
--- whatever image vanilla gave it.
local ICON_FOR = {
    optionBtn      = "Settings.png",
    centerBtn      = "Character.png",   -- "centre on me" is a person, not a "C"
    -- La rivista: e' l'icona della lettura in tutta la mod, la stessa
    -- dell'header del pannello che questo tasto fa aprire (NW_ReadWindow).
    printMediaBtn  = "Magazine.png",
    -- Il + e il - erano le lettere di vanilla ricentrate. Adesso sono icone
    -- della famiglia come il resto della fila: una lettera accanto a dieci
    -- disegni si legge come un tasto dimenticato.
    zoomInButton   = "ZoomIn.png",
    zoomOutButton  = "ZoomOut.png",
    -- Un cestino, non un punto interrogativo. Quel tasto cancella tutti i segni
    -- che hai messo sulla mappa, e un punto interrogativo e' il disegno
    -- universale di "cosa fa questo?": prometteva una spiegazione e invece
    -- buttava via il lavoro. Il cestino lo dice prima di premerlo.
    forgetBtn      = "Bin.png",
}

--- The first key that the game can actually translate, or the fallback.
local function tr(keys, fallback)
    for _, key in ipairs(keys) do
        local text = getText(key)
        if text and text ~= "" and text ~= key then return text end
    end
    return fallback
end

--- What each button says on hover.
---
--- Vanilla gives this row no tooltips at all - it labels the buttons "C", "S",
--- "P", "?" and leaves the player to guess. Icons without a name would be worse
--- than the letters, so every one gets a name here. Vanilla's own keys are used
--- wherever they exist: they are already translated into every language the
--- game ships.
local function tooltipFor(name)
    if name == "optionBtn" then
        return tr({ "IGUI_NW_MapOptions" }, "Map settings")
    elseif name == "nwLegendBtn" then
        return tr({ "IGUI_Map_Key", "IGUI_NW_Legend" }, "Legend")
    elseif name == "zoomInButton" then
        return tr({ "IGUI_Map_ZoomIn" }, "Zoom in")
    elseif name == "zoomOutButton" then
        return tr({ "IGUI_Map_ZoomOut" }, "Zoom out")
    elseif name == "terrainBtn" then
        return tr({ "IGUI_MapOption_TerrainImage" }, "Terrain")
    elseif name == "perspectiveBtn" then
        return tr({ "IGUI_NW_Perspective" }, "Perspective")
    elseif name == "nwFollowBtn" then
        return tr({ "IGUI_NW_Follow" }, "Follow me")
    elseif name == "centerBtn" then
        return tr({ "IGUI_NW_Center" }, "Centre on me")
    elseif name == "printMediaBtn" then
        return tr({ "IGUI_NW_PrintMedia" }, "Annotated maps")
    elseif name == "forgetBtn" then
        return tr({ "IGUI_NW_Forget" }, "Clear the map")
    end
    return nil
end

--- "Center Map" di TOYSGUNNER e' accesa? Si chiede come per Add More Map
--- Symbols (NW_Categories): l'id della mod, con e senza la barra davanti che
--- certe build aggiungono.
local function mapCenterActive()
    local ok, mods = pcall(getActivatedMods)
    if not ok or not mods then return false end
    return mods:contains("MapCenter") or mods:contains("\\MapCenter")
end

--- Buttons that simply should not be there any more.
local REMOVE = { "symbolsBtn", "closeBtn" }

local function paintButton(btn)
    local bg = NW_Style.tex("media/ui/NeatWriting/Button/Background.png")
    local brd = NW_Style.tex("media/ui/NeatWriting/Button/Boarder.png")

    local r, g, b = 0.2, 0.2, 0.2
    if btn.nwOn then
        r, g, b = NW_Style.accent.r, NW_Style.accent.g, NW_Style.accent.b
    end
    if btn.pressed then
        r, g, b = r * 0.8, g * 0.8, b * 0.8
    elseif btn:isMouseOver() then
        r, g, b = math.min(r * 1.5, 1), math.min(g * 1.5, 1), math.min(b * 1.5, 1)
    end

    if bg then
        btn:drawTextureScaled(bg, 0, 0, btn.width, btn.height, 0.85, r, g, b)
    else
        btn:drawRect(0, 0, btn.width, btn.height, 0.85, r, g, b)
    end
    if brd then
        btn:drawTextureScaled(brd, 0, 0, btn.width, btn.height, 1, 0.4, 0.4, 0.4)
    end

    local tex = btn.nwIcon or btn.image
    if tex then
        local s = math.floor(math.min(btn.width, btn.height) * ICON_FILL)
        btn:drawTextureScaled(tex, math.floor((btn.width - s) / 2),
            math.floor((btn.height - s) / 2), s, s, 1, 0.92, 0.92, 0.92)
    elseif btn.title and btn.title ~= "" then
        -- Un tasto senza icona nostra: la sua lettera, centrata.
        local fh = getTextManager():getFontHeight(UIFont.Medium)
        btn:drawTextCentre(btn.title, math.floor(btn.width / 2),
            math.floor((btn.height - fh) / 2),
            NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, UIFont.Medium)
    end
end

local function restyle(btn, iconName, name)
    if not btn then return end
    btn:setDisplayBackground(false)
    if iconName then
        btn.nwIcon = NW_Style.tex(ICONS .. iconName)
        btn.title = ""          -- the icon replaces the letter
    end
    btn.render = paintButton
    btn.prerender = function() end   -- vanilla's own background would show through

    -- After the empty prerender, never before: attach wraps whatever is there.
    local tip = name and tooltipFor(name)
    if tip then NW_Tooltip.attach(btn, tip) end
end

ISWorldMap.createChildren_prepatch_nwbuttons = ISWorldMap.createChildren
function ISWorldMap:createChildren()
    self:createChildren_prepatch_nwbuttons()

    -- Con la mappa lasciata al gioco la barra e' la sua: i tasti che togliamo
    -- servono di nuovo, perche' tornano a comandare i pannelli di vanilla.
    if NW.vanillaMap() then return end

    -- Vanilla ties the legend to the symbols panel, which we hide; without a
    -- button of its own it could never be opened again.
    if self.buttonPanel and not self.nwLegendBtn then
        local size = self.optionBtn and self.optionBtn:getHeight() or 32
        -- Whichever legend is in play: ours if Map Legend UI is installed
        -- (NW_Legend takes its place), vanilla's restyled one otherwise.
        local btn = ISButton:new(0, 0, size, size, "", self, function(map)
            local panel = map.nwLegend or map.keyUI
            if panel then panel:setVisible(not panel:isVisible()) end
        end)
        btn:initialise()
        btn:instantiate()
        self.buttonPanel:addChild(btn)
        self.nwLegendBtn = btn
    end

    -- CON "CENTER MAP" ATTIVA IL TASTO C DIVENTA DUE TASTI NOSTRI.
    --
    -- Quella mod si prende `centerBtn` e gli fa girare tre modi colorandolo di
    -- verde e di rosso; il nostro tasto e' ridisegnato da noi e quei colori non
    -- si vedevano, quindi il "centra" centrava, poi seguiva, poi non faceva
    -- niente, senza dire quale dei tre. Il suo tasto lo lasciamo a lei - nascosto,
    -- e lei continua a centrare la mappa quando si apre, che e' quello per cui la
    -- si installa - e ne mettiamo due che fanno una cosa sola ciascuno: la
    -- persona centra, l'elicottero segue (NW_Follow).
    if self.buttonPanel and mapCenterActive() and not self.nwCenterBtn then
        local size = self.optionBtn and self.optionBtn:getHeight() or 32
        local center = ISButton:new(0, 0, size, size, "", self, function(map)
            NW_Follow.center(map)
        end)
        center:initialise()
        center:instantiate()
        self.buttonPanel:addChild(center)
        self.nwCenterBtn = center

        local follow = ISButton:new(0, 0, size, size, "", self, function(map)
            NW_Follow.toggle(map)
        end)
        follow:initialise()
        follow:instantiate()
        self.buttonPanel:addChild(follow)
        self.nwFollowBtn = follow
    end

    local gone = {}
    for _, name in ipairs(REMOVE) do gone[#gone + 1] = name end
    if self.nwCenterBtn then gone[#gone + 1] = "centerBtn" end
    for _, name in ipairs(gone) do
        local b = self[name]
        if b then
            b:setVisible(false)
            b:setWidth(0)
            b:setX(-1000)   -- out of the row so shrinkWrap does not keep its space
        end
    end

    for name, icon in pairs(ICON_FOR) do
        restyle(self[name], icon, name)
    end
    restyle(self.nwLegendBtn, "Legend.png", "nwLegendBtn")
    restyle(self.nwCenterBtn, "Character.png", "centerBtn")
    restyle(self.nwFollowBtn, "Follow.png", "nwFollowBtn")
    if self.nwFollowBtn then
        -- Arancione finche' la vista segue: e' uno stato che dura, e senza una
        -- luce accesa si riapre la mappa senza ricordarsi perche' si muove.
        self.nwFollowBtn.render = function(b)
            b.nwOn = NW_Follow.isOn()
            paintButton(b)
        end
    end
    if self.printMediaBtn then
        -- Arancione finche' le icone di volantini e mappe annotate sono
        -- accese. Ridisegnato da noi il tasto non diceva in che stato fosse, e
        -- chi non vedeva icone lo premeva - spegnendole (segnalazione 42.21).
        self.printMediaBtn.render = function(b)
            local map = b.target
            b.nwOn = map ~= nil and map.showPrintMedia == true
            paintButton(b)
        end
    end
    restyle(self.terrainBtn, nil, "terrainBtn")
    restyle(self.perspectiveBtn, nil, "perspectiveBtn")
    if self.perspectiveBtn then
        -- LA VISTA IN CUI SI E', COME IN VANILLA: il tasto mostra la vista dall'alto
        -- o quella isometrica a seconda di com'e' la mappa adesso. Vanilla gli
        -- cambia l'immagine a ogni fotogramma; noi scegliamo la nostra dallo stesso
        -- campo (`isometric`, che vanilla aggiorna nel suo prerender). Le stesse
        -- due icone stanno sul tasto dei segni stesi del pannello (NW_Panel).
        self.perspectiveBtn.render = function(b)
            local map = b.target
            b.nwIcon = NW_Style.tex(ICONS .. ((map and map.isometric)
                and "ViewIsometric.png" or "ViewTop.png"))
            paintButton(b)
        end
    end

    -- The bar was laid out with the two removed buttons still in it, so it has
    -- to be measured again or it keeps a gap where they used to be.
    --
    -- E i tasti crescono. Vanilla li fa larghi quanto la sua texture, 48, e
    -- dentro ci disegniamo l'icona al 62%: trenta pixel scarsi, che per un
    -- cestino bastano e per il disegno a linee sottili della prospettiva no -
    -- quello e' un cubetto in prospettiva, e a trenta pixel non si capisce cosa
    -- sia. La fila e' in fondo a uno schermo intero e lo spazio c'e'.
    if self.buttonPanel then
        local x = 0
        for _, name in ipairs({ "optionBtn", "nwLegendBtn", "zoomInButton",
                "zoomOutButton", "terrainBtn", "perspectiveBtn", "centerBtn",
                "nwCenterBtn", "nwFollowBtn",
                "printMediaBtn", "forgetBtn" }) do
            local b = self[name]
            if b and b:isVisible() then
                b:setWidth(BTN_SIZE)
                b:setHeight(BTN_SIZE)
                b:setX(x)
                b:setY(0)
                x = x + BTN_SIZE + BTN_GAP
            end
        end
        self.buttonPanel:setWidth(math.max(0, x - BTN_GAP))
        self.buttonPanel:setHeight(BTN_SIZE)
        self.buttonPanel:setX(self.width - 10 - self.buttonPanel:getWidth())
        self.buttonPanel:setY(self.height - 10 - BTN_SIZE)
    end
end
