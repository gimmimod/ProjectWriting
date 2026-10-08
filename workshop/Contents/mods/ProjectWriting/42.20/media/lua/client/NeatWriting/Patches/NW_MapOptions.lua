--[[ ============================================================================
    NW_MapOptions - the world map's settings panel, in the family's clothes.

    WorldMapOptions carries real logic: which options are visible at which
    access level, joypad navigation, reading and writing the core settings. None
    of that is touched, and no option is added or removed - a future build that
    adds one gets it for free. Only the surfaces and the arrangement are ours.

    The brightness row is the one real change. Vanilla spends three lines on it:
    a "BRIGHTNESS" caption, the number, and the slider - and our slider already
    prints its own value, so the number appeared twice. Now it is one line.

    E IL SOLE E' DIVENTATO UN TASTO. Stava li' a fare da parola "luminosita'",
    disegnato e non cliccabile; adesso e' l'interruttore fra giorno e notte, e
    premendolo diventa una luna. Le due cose non si pestano i piedi:
    l'interruttore sceglie di che colore e' la mappa, il cursore quanta luce le
    arriva, ed e' la stessa coppia che ha qualunque schermo. Sotto, una casella
    sola: quella che lascia decidere all'ora del mondo.

    Everything is then laid out again from scratch. Vanilla sizes the window by
    walking its children and taking the furthest edge, which is why it came out
    as a tall box with a wide empty margin down the right.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISTickBox"
require "ISUI/Maps/ISWorldMap"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Style"
require "NeatWriting/NW_DarkMap"
require "NeatWriting/UI/NW_Slider"
require "NeatWriting/UI/NW_Tooltip"

local FONT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local FONT_SMALL  = getTextManager():getFontHeight(UIFont.Small)

local PAD      = 12   -- window edge to content
local ROW_GAP  = 7    -- between tick boxes
local BLOCK_GAP = 12  -- between the brightness row and the list
local SUN_GAP  = 9    -- fra l'interruttore e il cursore
local SLIDER_H = FONT_SMALL + 10
local MIN_SLIDER_W = 200
local HEADER_H = math.floor(FONT_MEDIUM * 1.5)

--- The title bar, at the height the rest of the family uses.
---
--- Vanilla returns max(16, small font + 1), which is 16 - and the title is
--- drawn in Medium, so it was hanging out of its own bar. Overriding the method
--- rather than the number means the close button and the drag area follow,
--- because vanilla asks this same question for both.
WorldMapOptions.titleBarHeight_prepatch_neatwriting = WorldMapOptions.titleBarHeight
function WorldMapOptions:titleBarHeight()
    if NW.vanillaMap() then return self:titleBarHeight_prepatch_neatwriting() end
    return HEADER_H
end

--- L'icona dell'interruttore segue lo stato. Si rimette a ogni disposizione
--- perche' la preferenza puo' essere stata cambiata da una mappa aperta prima di
--- questa, e a ogni fotogramma perche' con la notte automatica puo' cambiare da
--- sola mentre questa finestra e' aperta: un sole disegnato su una mappa scura
--- sarebbe un tasto che mente.
---
--- Dichiarata qui e non piu' in basso perche' la usa gia' il prerender: una
--- `local function` chiamata prima di essere dichiarata e' un global nil, e
--- nessuno strumento la vede (lezione 18).
local function syncSwitch(self)
    if not self.nwDarkBtn then return end
    local on = NW_DarkMap.isOn()
    if self.nwDarkOn == on then return end
    self.nwDarkOn = on
    NW_Style.setButtonIcon(self.nwDarkBtn,
        NW_Style.tex(NW.ICONS .. (on and "Moon.png" or "Sun.png")))
    NW_Style.setButtonActive(self.nwDarkBtn, on)
end

--- ISCollapsableWindow paints its own frame and title bar. Ours replaces both,
--- so the vanilla painter is never called.
WorldMapOptions.prerender_prepatch_neatwriting = WorldMapOptions.prerender
function WorldMapOptions:prerender()
    if NW.vanillaMap() then return self:prerender_prepatch_neatwriting() end
    local headerH = self:titleBarHeight()
    NW_Style.drawWindow(self, 0, 0, self.width, self.height, headerH)

    syncSwitch(self)

    local pad = NW_Style.headerPadding(headerH)
    local iconSize = NW_Style.headerIconSize(headerH)
    local tx = pad
    local icon = NW_Style.tex(NW.ICONS .. "Settings.png")
    if icon then
        self:drawTextureScaled(icon, pad, math.floor((headerH - iconSize) / 2),
            iconSize, iconSize, 1, NW_Style.text.r, NW_Style.text.g, NW_Style.text.b)
        tx = pad + iconSize + NW_Style.headerGap(headerH)
    end
    -- Our own key: there is no vanilla string for this panel's title, which is
    -- why the raw "IGUI_Map_Options" was showing through.
    self:drawText(getText("IGUI_NW_MapOptions"), tx,
        math.floor((headerH - FONT_MEDIUM) / 2),
        NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, UIFont.Medium)

    -- Il blocco della luce si chiude con una linea, come ogni blocco della
    -- famiglia. Il sole non si disegna piu' qui: adesso e' un figlio, e i figli
    -- si disegnano da soli, fra questo prerender e il render.
    local last = self.nwAutoBox or self.nwSlider
    if last then
        NW_Style.drawRule(self, PAD, last:getBottom() + math.floor(BLOCK_GAP / 2),
            self.width - PAD * 2)
    end
end

--- Nothing: vanilla's render ends with
---
---     self:drawRectBorder(0, 0, self:getWidth(), height, ...)
---
--- a square border around the whole window, drawn on top of our rounded
--- nine-patch. That is what was squaring off the corners - the panel underneath
--- was round all along. The rest of that function is the resize widget, which
--- WorldMapOptions never shows, and the joypad focus ring.
WorldMapOptions.render_prepatch_neatwriting = WorldMapOptions.render
function WorldMapOptions:render()
    if NW.vanillaMap() then return self:render_prepatch_neatwriting() end
end

--- Il sole, che adesso si preme.
---
--- IL DISEGNO LO DICE DA SE': c'e' un sole, si preme, diventa una luna. E' il
--- posto giusto perche' e' dove il sole stava gia' - solo che prima era una
--- figura buona a dire "luminosita'" e nient'altro, e chi ci provava sopra non
--- otteneva niente.
---
--- Convive col cursore accanto senza sovrapporsi: l'interruttore decide di che
--- colore e' la mappa, il cursore quanta luce le arriva. Chi vuole una notte
--- appena accennata accende la luna e alza il cursore; chi la vuole fonda fa il
--- contrario.
local function makeSwitch(self, x, y)
    if not self.nwDarkBtn then
        local b = NW_Style.newSquareButton(x, y, SLIDER_H, nil, self,
            function() NW_MapOptions_toggleDark(self) end)
        self:addChild(b)
        self.nwDarkBtn = b
        NW_Tooltip.attach(b, getText("IGUI_NW_DarkMap"))
    end
    self.nwDarkOn = nil
    syncSwitch(self)
    self.nwDarkBtn:setX(x)
    self.nwDarkBtn:setY(y)
    self.nwDarkBtn:setWidth(SLIDER_H)
    self.nwDarkBtn:setHeight(SLIDER_H)
end

--- E sotto l'interruttore, chi lo puo' premere al posto nostro.
---
--- Sta qui e non fra le opzioni della mod perche' e' la stessa domanda del
--- tasto accanto - di che colore e' la mappa - e le due si guardano. Non e' una
--- casella di vanilla: quelle le costruisce `createChildren` da una lista di
--- opzioni del gioco, questa e' nostra e vive accanto a loro senza entrarci.
local function makeAuto(self, x, y, w, h)
    if not self.nwAutoBox then
        local tb = ISTickBox:new(x, y, w, h, "", self, function(_, _, selected)
            NW.setDarkAuto(selected and true or false)
        end)
        tb:initialise()
        tb:addOption(getText("IGUI_NW_DarkAuto"))
        self:addChild(tb)
        NW_Style.styleTickBox(tb)
        NW_Tooltip.attach(tb, getText("IGUI_NW_DarkAutoTip"))
        self.nwAutoBox = tb
    end
    -- Riletta a ogni apertura: la preferenza sta in un file, non in questa
    -- finestra, e puo' essere cambiata da un'altra partita.
    self.nwAutoBox:setSelected(1, NW.darkAuto())
    self.nwAutoBox:setX(x)
    self.nwAutoBox:setY(y)
    self.nwAutoBox:setWidth(w)
    self.nwAutoBox:setHeight(h)
    return self.nwAutoBox
end

--- Preme l'interruttore: la mappa sotto cambia, questa finestra cambia icona.
---
--- E' una globale e non un metodo perche' `WorldMapOptions` e' una classe di
--- vanilla: aggiungerle un metodo nostro vuol dire scommettere che nessuno,
--- oggi o fra due build, chiami un suo metodo con lo stesso nome (lezione 16).
function NW_MapOptions_toggleDark(self)
    local map = rawget(_G, "ISWorldMap_instance")
    NW_DarkMap.toggle(map)
    syncSwitch(self)
end

--- Swaps vanilla's brightness slider for ours - the same control the pen width
--- uses, so a slider is a slider everywhere in the mod.
local function replaceSlider(self, x, y, w)
    local old = self.darkModeSlider
    if not old then return end

    old:setVisible(false)
    old:setX(-10000)   -- out of the way; vanilla still holds a reference to it

    if not self.nwSlider then
        local sl = NW_Slider:new(x, y, w, SLIDER_H, self, function(_, value)
            getCore():setOptionWorldMapBrightness(value / 100)
        end)
        sl:initialise()
        sl:instantiate()
        sl.minValue, sl.maxValue, sl.step = 0, 100, 1
        sl.mode, sl.suffix = "value", ""
        sl.previewW = 44
        sl:setValue((getCore():getOptionWorldMapBrightness() or 1) * 100, true)
        self:addChild(sl)
        self.nwSlider = sl
    end
    self.nwSlider:setX(x)
    self.nwSlider:setY(y)
    self.nwSlider:setWidth(w)
end

--- Vanilla's two captions for the brightness row. One says "BRIGHTNESS", the
--- other repeats the number our slider already prints.
local function hideBrightnessLabels(self)
    if self.darkModeLabel then
        self.darkModeLabel:setVisible(false)
        self.darkModeLabel:setX(-10000)
    end
    local caption = getText("IGUI_Map_Brightness")
    for _, child in pairs(self:getChildren() or {}) do
        if child ~= self.darkModeLabel and child.name == caption then
            child:setVisible(false)
            child:setX(-10000)
        end
    end
end

--- The tick boxes, in the order vanilla laid them out.
---
--- self.tickBoxes is built with table.insert(t, i, box) where i counts every
--- visible option, boolean or not - so a non-boolean one leaves a hole, and
--- ipairs would stop at it and quietly drop every box after. Taken once, sorted
--- by where vanilla put them, and kept.
local function boxesOf(self)
    local out = {}
    for _, box in pairs(self.tickBoxes or {}) do
        out[#out + 1] = { box = box, y = box:getY(), x = box:getX() }
    end
    -- Cached, but thrown away if vanilla ever hands us a different set.
    if self.nwBoxes and #self.nwBoxes == #out then return self.nwBoxes end
    table.sort(out, function(a, b)
        if a.x ~= b.x then return a.x < b.x end   -- vanilla wraps into columns
        return a.y < b.y
    end)
    self.nwBoxes = {}
    for i, entry in ipairs(out) do self.nwBoxes[i] = entry.box end
    return self.nwBoxes
end

--- Everything the panel shows, placed by us. One column: the brightness row, a
--- rule, then the tick boxes.
local function relayout(self)
    local headerH = self:titleBarHeight()
    local boxes = boxesOf(self)

    -- La casella nostra si costruisce PRIMA di misurare la finestra, e si fa
    -- dire quanto le serve: "Automatic at nightfall" in inglese ci sta,
    -- "Automatica al calar della notte" in italiano no, e in tedesco meno
    -- ancora. La larghezza la decide la frase piu' lunga fra quelle che ci
    -- sono davvero, non una misura scelta guardando l'inglese.
    local rowH = boxes[1] and boxes[1]:getHeight() or SLIDER_H
    local auto = makeAuto(self, PAD, headerH + PAD, MIN_SLIDER_W, rowH)
    auto:setWidthToFit()

    -- Width comes from the widest thing that has to fit, not from wherever
    -- vanilla happened to leave a child.
    local content = MIN_SLIDER_W + SLIDER_H + SUN_GAP
    content = math.max(content, auto:getWidth())
    for _, box in ipairs(boxes) do
        content = math.max(content, box:getWidth())
    end
    self:setWidth(content + PAD * 2)

    -- Placed here rather than where it is recoloured: it hangs off the right
    -- edge, and the right edge is only known once the width is.
    if self.closeButton then
        local size = NW_Style.headerButtonSize(headerH)
        local pad = NW_Style.headerPadding(headerH)
        self.closeButton:setWidth(size)
        self.closeButton:setHeight(size)
        self.closeButton:setX(self.width - size - pad)
        self.closeButton:setY(math.floor((headerH - size) / 2))
    end

    local y = headerH + PAD
    makeSwitch(self, PAD, y)
    replaceSlider(self, PAD + SLIDER_H + SUN_GAP, y, content - SLIDER_H - SUN_GAP)
    y = y + SLIDER_H + ROW_GAP

    -- Adesso che la larghezza c'e', la casella si prende tutta la riga: cosi'
    -- il tocco prende dove si vede, non solo sopra le lettere.
    auto:setY(y)
    auto:setWidth(content)
    y = auto:getBottom() + BLOCK_GAP

    for _, box in ipairs(boxes) do
        box:setX(PAD)
        box:setY(y)
        box:setWidth(content)
        y = y + box:getHeight() + ROW_GAP
    end

    -- No allowance for the resize widget: WorldMapOptions sets resizable=false,
    -- so vanilla was reserving a strip for a handle it never draws.
    self:setHeight(y - ROW_GAP + PAD)
end

--- Widgets do not exist until createChildren has run, so styling waits for the
--- first time the panel is shown.
local function styleWidgets(self)
    if not self.nwStyled then
        self.nwStyled = true
        -- boxesOf reads where vanilla put them, so it has to run before we move
        -- anything.
        for _, box in ipairs(boxesOf(self)) do
            NW_Style.styleTickBox(box)
        end
        hideBrightnessLabels(self)

        if self.closeButton then
            local icon = NW_Style.iconClose()
            if icon and self.closeButton.setImage then self.closeButton:setImage(icon) end
            self.closeButton.backgroundColor = { r = 0.80, g = 0.20, b = 0.20, a = 0.9 }
            self.closeButton.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
        end
    end
    -- Run every time: which options are visible depends on access level, and
    -- the player can be promoted without the panel being rebuilt.
    relayout(self)
end

--- Sopra la fila dei tasti, non addosso.
---
--- Vanilla mette il bordo di sotto ESATTAMENTE sul bordo di sopra del tasto che
--- l'ha aperta (`setY(button.parent.y + button.y - height)`), e lo fa PRIMA di
--- mostrarla: cioe' prima che noi la disponiamo e le si cambi l'altezza. Da li'
--- in poi quella y non e' piu' la sua, e la finestra scende sui tasti. Si
--- rimette adesso, che l'altezza e' quella definitiva, con un dito d'aria in
--- mezzo: una finestra che tocca i tasti sembra sempre averli coperti per
--- sbaglio.
local BAR_GAP = 10

local function placeAbove(self)
    local map = self.map
    local bar = map and map.buttonPanel
    if not bar then return end
    self:setY(math.max(0, bar:getY() - self:getHeight() - BAR_GAP))
    -- E dentro il bordo anche di lato: la finestra si allarga quanto le serve
    -- per la lingua che c'e', e allargandosi verso destra ne uscirebbe.
    local right = (map:getWidth() or self:getRight()) - PAD
    if self:getRight() > right then
        self:setX(math.max(0, right - self:getWidth()))
    end
end

WorldMapOptions.setVisible_prepatch_neatwriting = WorldMapOptions.setVisible
function WorldMapOptions:setVisible(visible, joypadData)
    if visible and not NW.vanillaMap() then
        styleWidgets(self)
        placeAbove(self)
    end
    return self:setVisible_prepatch_neatwriting(visible, joypadData)
end
