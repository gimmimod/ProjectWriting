--[[ ============================================================================
    NW_Style - every pixel Project Writing paints goes through here.

    Anatomy is the family's (METODO/01_STILE_NEATUI): a MainTitle_BG header over
    a MainPanelBG_FlatTop body, grey tints 0.08 / 0.15, InnerPanel_BG for the
    groups, orange reserved for active states, green for what is selected.

    TEXTURES come only from copies bundled under media/ui/NeatWriting/. They
    used to resolve framework-first: NeatUI_Framework is a Workshop mod and may
    simply not be enabled - without a copy every nine-patch degrades to a flat
    rectangle, which is how the panel once lost its rounded corners - and with
    it enabled the look depended on a version we do not ship. Now there is one
    source, ours, for panels, buttons and the Clean HotBar slots.

    NinePatchTexture.getSharedTexture is called inline, fresh, every frame: it is
    already the shared cache, and caching a nil from the first frames leaves the
    panel square for the whole session (METODO/03 lesson 1).
============================================================================ ]]--

if isServer() then return end

NW_Style = NW_Style or {}
local S = NW_Style

S.accent    = { r = 0.95, g = 0.50, b = 0.10 }
S.close     = { r = 0.80, g = 0.20, b = 0.20 }
S.selection = { r = 0.30, g = 0.72, b = 0.38 }
S.text      = { r = 0.90, g = 0.90, b = 0.90 }
S.dim       = { r = 0.58, g = 0.58, b = 0.61 }
S.frame     = { r = 0.34, g = 0.34, b = 0.36 }

S.TINT_HEADER = 0.08
S.TINT_BODY   = 0.15

S.HEADER = { button = 0.80, icon = 0.64, pad = 0.16, gap = 0.07 }

function S.headerButtonSize(h) return math.max(15, math.floor(h * S.HEADER.button)) end
function S.headerIconSize(h)   return math.max(10, math.floor(h * S.HEADER.icon))   end
function S.headerPadding(h)    return math.max(3,  math.floor(h * S.HEADER.pad))    end
function S.headerGap(h)        return math.max(2,  math.floor(h * S.HEADER.gap))    end

-- ---------------------------------------------------------------------------
-- La scala dei caratteri
-- ---------------------------------------------------------------------------
--
-- Il pannello si tira per l'angolo, quindi ogni scritta deve prendere il
-- carattere piu' grande che ci sta ancora nella riga che la ospita: senza
-- questo un pannello al doppio della misura resta con le stesse letterine di
-- prima, in mezzo a un mare di vuoto - che e' esattamente il difetto per cui
-- la maniglia e' stata chiesta, a rovescio.
--
-- La scaletta si costruisce alla prima richiesta e non prima: UIFont e' una
-- enum Java, e non tutte le build espongono gli stessi nomi. E' la stessa
-- ricetta di XP Drop (NeatXPStyle.pickFont).
local _ladder = nil

local function buildLadder()
    local tm = getTextManager()
    local seen, out = {}, {}
    for _, name in ipairs({ "Small", "NewSmall", "Medium", "NewMedium", "Large", "NewLarge" }) do
        local ok, font = pcall(function() return UIFont[name] end)
        if ok and font ~= nil then
            local ok2, h = pcall(function() return tm:getFontHeight(font) end)
            if ok2 and type(h) == "number" and h > 0 and not seen[h] then
                seen[h] = true
                table.insert(out, { font = font, h = h })
            end
        end
    end
    if #out == 0 then out = { { font = UIFont.Small, h = tm:getFontHeight(UIFont.Small) } } end
    table.sort(out, function(a, b) return a.h < b.h end)
    return out
end

--- Il carattere piu' grande che sta in `maxH`, e la sua altezza.
--- Mai piu' piccolo del piu' piccolo che c'e': una scritta troppo grande si
--- taglia, una che sparisce non si taglia - non c'e' piu'.
function S.pickFont(maxH)
    if _ladder == nil then _ladder = buildLadder() end
    local chosen = _ladder[1]
    for _, e in ipairs(_ladder) do
        if e.h <= maxH then chosen = e else break end
    end
    return chosen.font, chosen.h
end

-- TUTTO DA DENTRO LA MOD. Pannelli, tasti e slot sono copie dei file di NeatUI
-- Framework e di Clean HotBar, e si leggono solo da qui: prima si provava la
-- cartella di quelle mod e poi la nostra, e con quelle mod installate la
-- faccia del pannello dipendeva da una versione che non controlliamo. Adesso
-- Project Writing si vede uguale con o senza di loro, e non ne chiede nessuna.
local OWN = "media/ui/NeatWriting/"

local PANEL = {
    body   = { OWN .. "Panel/MainPanelBG_FlatTop.png" },
    round  = { OWN .. "Panel/MainPanelBG_RoundTop.png" },
    header = { OWN .. "Panel/MainTitle_BG.png" },
    inner  = { OWN .. "Panel/InnerPanel_BG.png" },
}
local BTN = {
    bg     = { OWN .. "Button/Background.png" },
    border = { OWN .. "Button/Boarder.png" },
    -- Le tre fette del tasto largo. Il cappuccio sinistro e quello destro si
    -- disegnano alla loro misura, il centro si stira: e' cosi' che un tasto
    -- lungo tiene gli angoli tondi come uno corto. Stirare un'immagine sola,
    -- come si fa per una cella quadrata, la trasforma in una losanga.
    l      = { OWN .. "Button/Button_FULL_L.png" },
    m      = { OWN .. "Button/Button_FULL_M.png" },
    r      = { OWN .. "Button/Button_FULL_R.png" },
}
-- Lo slot di Clean HotBar (CleanHotbar_Slot_BG, _Slot_ItemBorder, _Item_Hover),
-- gli stessi byte che usa anche NeatUI Equipment.
local SLOT = {
    bg     = { OWN .. "Slot/Slot_BG.png" },
    border = { OWN .. "Slot/Slot_Border.png" },
    glow   = { OWN .. "Slot/Slot_Hover.png" },
}
local ICON_CLOSE = { OWN .. "Icon_False.png" }
local ICON_TICK  = { OWN .. "Icon_True.png" }

local _texCache = {}

--- Never cached: getSharedTexture can return nil on the first frames, and a
--- cached nil leaves the panel square for the rest of the session.
local function NP(list)
    if not NinePatchTexture then return nil end
    for _, path in ipairs(list) do
        local ok, res = pcall(function() return NinePatchTexture.getSharedTexture(path) end)
        if ok and res then return res end
    end
    return nil
end

local function TEX(list)
    local paths = type(list) == "table" and list or { list }
    local key = paths[1]
    local c = _texCache[key]
    if c ~= nil then return c or nil end
    for _, p in ipairs(paths) do
        local ok, res = pcall(getTexture, p)
        if ok and res and res.getWidth and res:getWidth() > 0 then
            _texCache[key] = res
            return res
        end
    end
    _texCache[key] = false
    return nil
end

S.tex = TEX

-- ---------------------------------------------------------------------------
-- Panel surfaces
-- ---------------------------------------------------------------------------

--- The whole window in one call, the way Rocco builds one: rounded-top header
--- strip over a flat-top body, with the black hairline that separates the tints.
function S.drawWindow(el, x, y, w, h, headerH)
    local hdr = NP(PANEL.header)
    if hdr then
        local c = S.TINT_HEADER
        hdr:render(el:getAbsoluteX() + x, el:getAbsoluteY() + y, w, headerH, c, c, c, 1.0)
    else
        el:drawRect(x, y, w, headerH, 1, 0.07, 0.07, 0.08)
    end

    local body = NP(PANEL.body)
    if body then
        local c = S.TINT_BODY
        body:render(el:getAbsoluteX() + x, el:getAbsoluteY() + y + headerH,
            w, h - headerH, c, c, c, 1.0)
    else
        el:drawRect(x, y + headerH, w, h - headerH, 1, 0.13, 0.13, 0.14)
        el:drawRectBorder(x, y + headerH, w, h - headerH, 1, S.frame.r, S.frame.g, S.frame.b)
    end

    el:drawRect(x, y + headerH - 1, w, 1, 1, 0, 0, 0)
end

--- The label inside a window header: icon on the left, title beside it.
---
--- Three panels were drawing this by hand with the same six lines - the Writing
--- panel, the sharing panel, the naming panel - and the third copy is what makes
--- it a pattern rather than a coincidence. The measures come from S.HEADER, so
--- an icon here and an icon there cannot drift apart.
---
--- `icon` may be nil: then the title starts at the padding, and nothing is left
--- hanging where a picture used to be.
function S.drawHeaderLabel(el, headerH, icon, title, font, fontH)
    local pad = S.headerPadding(headerH)
    local tx = pad
    if icon then
        local size = S.headerIconSize(headerH)
        el:drawTextureScaled(icon, pad, math.floor((headerH - size) / 2),
            size, size, 1, S.text.r, S.text.g, S.text.b)
        tx = pad + size + S.headerGap(headerH)
    end
    if title and title ~= "" then
        el:drawText(title, tx, math.floor((headerH - (fontH or 0)) / 2),
            S.text.r, S.text.g, S.text.b, 1, font)
    end
    return tx
end

--- A group box: InnerPanel_BG at tint 0.10, the same one Equipment uses
--- (NEQ_Style.drawInnerPanel). A nine-patch keeps its corners at any size; a
--- stretched sprite comes out squashed, which is what happened here first.
function S.drawGroup(el, x, y, w, h, alpha)
    local t = NP(PANEL.inner)
    if t then
        t:render(el:getAbsoluteX() + x, el:getAbsoluteY() + y, w, h,
            0.10, 0.10, 0.10, alpha or 0.9)
        return
    end
    el:drawRect(x, y, w, h, alpha or 0.9, 0.10, 0.10, 0.11)
    el:drawRectBorder(x, y, w, h, 0.5, 0.28, 0.28, 0.30)
end

function S.drawRule(el, x, y, w)
    el:drawRect(x, y, w, 1, 0.45, 0.40, 0.40, 0.42)
end

-- ---------------------------------------------------------------------------
-- Buttons and tiles
-- ---------------------------------------------------------------------------

--- Square icon button. Uses the framework widget when it is loaded, a styled
--- ISButton otherwise. `tint` makes it permanently coloured - how the family
--- draws a close button: red and always lit (NR_Header:265).
function S.newSquareButton(x, y, size, icon, target, onclick, tint)
    local SB = rawget(_G, "NI_SquareButton")
    if SB then
        local b = SB:new(x, y, size, icon, target, onclick)
        b:initialise()
        b:instantiate()
        b:setActive(tint ~= nil)
        local c = tint or S.accent
        b:setActiveColor(c.r, c.g, c.b)
        b.nwFixedTint = tint ~= nil
        return b
    end
    local b = ISButton:new(x, y, size, size, "", target, onclick)
    b:initialise()
    b:instantiate()
    b:setDisplayBackground(false)
    b.nwIcon = icon
    b.nwActive = tint ~= nil
    b.nwTint = tint
    b.nwFixedTint = tint ~= nil
    b.render = S.renderSquareFallback
    return b
end

function S.renderSquareFallback(btn)
    local bg, brd = TEX(BTN.bg), TEX(BTN.border)
    local r, g, b = 0.2, 0.2, 0.2
    if btn.nwActive then
        local c = btn.nwTint or S.accent
        r, g, b = c.r, c.g, c.b
    end
    if btn.pressed then
        r, g, b = r * 0.8, g * 0.8, b * 0.8
    elseif btn:isMouseOver() then
        r, g, b = math.min(r * 1.5, 1), math.min(g * 1.5, 1), math.min(b * 1.5, 1)
    end
    if bg then
        btn:drawTextureScaled(bg, 0, 0, btn.width, btn.height, 0.8, r, g, b)
    else
        btn:drawRect(0, 0, btn.width, btn.height, 0.8, r, g, b)
    end
    if brd then
        btn:drawTextureScaled(brd, 0, 0, btn.width, btn.height, 1, 0.4, 0.4, 0.4)
    end
    if btn.nwIcon then
        local s = math.floor(math.min(btn.width, btn.height) * 0.8)
        btn:drawTextureScaled(btn.nwIcon, math.floor((btn.width - s) / 2),
            math.floor((btn.height - s) / 2), s, s, 1, 0.9, 0.9, 0.9)
    end
end

--- Swaps the picture on a square button. The framework widget keeps its icon
--- in the Java object, our fallback in a field: both roads are one line, and
--- the caller should not have to know which button it got.
function S.setButtonIcon(btn, icon)
    if not btn or not icon then return end
    btn.nwIcon = icon
    if btn.setImage then pcall(function() btn:setImage(icon) end) end
    if btn.setIcon then pcall(function() btn:setIcon(icon) end) end
end

--- The ground behind a rename field: the same inner panel as a group box, a
--- step darker, so an editable row still reads as the row it replaced instead
--- of a vanilla box that landed on top of it.
function S.drawTextField(el, x, y, w, h)
    local t = NP(PANEL.inner)
    if t then
        t:render(el:getAbsoluteX() + x, el:getAbsoluteY() + y, w, h, 0.06, 0.06, 0.06, 1)
    else
        el:drawRect(x, y, w, h, 1, 0.06, 0.06, 0.07)
    end
    el:drawRect(x, y + h - 1, w, 1, 0.8, S.accent.r, S.accent.g, S.accent.b)
end

function S.setButtonActive(btn, active)
    if not btn then return end
    if btn.nwFixedTint then return end
    if btn.setActive then btn:setActive(active) end
    btn.nwActive = active
end

--- LO SLOT DI UNO STRUMENTO, con la ricetta di Clean HotBar.
---
--- Il fondo e' la sua texture sfumata ai bordi, grigia come nella barra rapida;
--- sopra, lo stesso fondo tinto del colore dell'inchiostro, che riempie tutto lo
--- slot come il liquido riempie una bottiglia nella barra di Clean HotBar - li'
--- fino al livello, qui fino in cima, perche' una penna o scrive o non c'e'.
--- Poi il bagliore e il bordo, che porta lo stato: verde per quello in mano,
--- arancione sotto il mouse, grigio a riposo.
---
--- `opts.fills`   i colori, uno per inchiostro. Piu' di uno (la penna a quattro
---                colori, i pastelli) si dividono lo slot in colonne: si ritaglia
---                la stessa texture con lo stencil, cosi' le colonne tengono i
---                bordi sfumati dello slot invece di tagliarli dritti.
--- `opts.current` l'indice del colore in uso: gli altri si velano, e parecchio
---                (0.30), perche' a 0.45 le quattro colonne sembravano ancora
---                quattro scelte uguali. Senza (lo strumento non e' in mano) le
---                colonne sono tutte piene.
--- `opts.badge`   una texture da mettere piccola nell'angolo in alto a destra, e
---                allora il colore NON si stende: e' la matita girata sulla
---                gomma, che in quel momento non scrive niente. Prima il colore
---                restava, velato, e nell'anteprima era indistinguibile dalla
---                matita dritta; una casella grigia con la gommetta nell'angolo
---                dice "adesso cancella" senza bisogno di confrontarla.
---
--- Le misure sono state scelte su un'anteprima composta come la compone il
--- motore - texel per tinta, alfa per alfa - con le icone vere del gioco.
function S.drawSlot(el, x, y, w, h, opts)
    opts = opts or {}
    local bg = TEX(SLOT.bg)
    local base = opts.hover and 0.50 or 0.35
    if bg then
        el:drawTextureScaled(bg, x, y, w, h, 0.6, base, base, base)
    else
        el:drawRect(x, y, w, h, 0.6, base * 0.4, base * 0.4, base * 0.4)
    end

    local fills = opts.fills or {}
    local n = #fills
    if n > 0 and not opts.badge then
        local strong = opts.hover and 0.95 or 0.85
        local soft = 0.30
        local cw = w / n
        for i, c in ipairs(fills) do
            local a = strong
            if n > 1 and opts.current and opts.current ~= i then a = soft end
            if n > 1 then
                local cx0 = math.floor(x + (i - 1) * cw)
                local cx1 = (i == n) and (x + w) or math.floor(x + i * cw)
                el:setStencilRect(cx0, y, cx1 - cx0, h)
            end
            if bg then
                el:drawTextureScaled(bg, x, y, w, h, a, c.r, c.g, c.b)
            else
                el:drawRect(x, y, w, h, a, c.r, c.g, c.b)
            end
            if n > 1 then el:clearStencilRect() end
        end
    end

    local glow = TEX(SLOT.glow)
    if glow then el:drawTextureScaled(glow, x, y, w, h, 0.6, 0.98, 0.95, 0.85) end

    local brd = TEX(SLOT.border)
    local c, a = { r = 0.6, g = 0.6, b = 0.6 }, 0.6
    if opts.selected then c, a = S.selection, 1.0
    elseif opts.hover then c, a = S.accent, 0.85 end
    if opts.badge then
        local bs = math.floor(w * 0.42)
        el:drawTextureScaled(opts.badge, x + w - bs - 2, y + 2, bs, bs, 1, 0.9, 0.9, 0.9)
    end
    if brd then
        el:drawTextureScaled(brd, x, y, w, h, a, c.r, c.g, c.b)
    else
        el:drawRectBorder(x, y, w, h, a, c.r, c.g, c.b)
    end
end

--- A tile: rounded ground, and a border that carries the whole state. No fill
--- flash on selection - the border already says it, and a second signal for one
--- state reads as two things happening.
function S.drawTile(el, x, y, w, h, selected, hovered)
    local bg = TEX(BTN.bg)
    if bg then
        el:drawTextureScaled(bg, x, y, w, h, 0.85, 0.155, 0.16, 0.175)
    else
        el:drawRect(x, y, w, h, 0.85, 0.155, 0.16, 0.175)
    end
    local c = S.frame
    if selected then c = S.selection elseif hovered then c = S.accent end
    local brd = TEX(BTN.border)
    if brd then
        el:drawTextureScaled(brd, x, y, w, h, 1, c.r, c.g, c.b)
    else
        el:drawRectBorder(x, y, w, h, 1, c.r, c.g, c.b)
    end
end

--- Three slices, crisp caps and a stretched middle. XP Drop's `draw3`.
local function draw3(el, tl, tm, tr, x, y, w, h, capW, a, r, g, b)
    capW = math.min(capW, math.floor(w / 2))
    if capW < 1 then capW = 1 end
    el:drawTextureScaled(tl, x, y, capW, h, a, r, g, b)
    local midW = w - capW * 2
    if midW > 0 and tm then el:drawTextureScaled(tm, x + capW, y, midW, h, a, r, g, b) end
    el:drawTextureScaled(tr, x + w - capW, y, capW, h, a, r, g, b)
end

--- A WIDE BUTTON - a row in a list, a slot in a settings panel.
---
--- The recipe is XP Drop's `NeatXPStyle.drawButton`, which is the framework's
--- own `NI_SquareButton`: three slices, and the four greys 0.20 / 0.30 / 0.10
--- at alpha 0.8. Not invented here, and not a nine-patch either - a first pass
--- used `drawTile`, which stretches one button sprite, and a row three hundred
--- pixels wide came out a lozenge.
---
--- ORANGE IS THE ACTIVE STATE, and that is the family's rule, not a choice made
--- for this panel: green marks what is selected right now, orange marks what
--- stays switched on after you look away. A sharing preset is exactly that.
---
--- `state`: nil / "hover" / "pressed" / "active" / "activeHover".
function S.drawWideButton(el, x, y, w, h, state)
    local r, g, b, a = 0.20, 0.20, 0.20, 0.8
    if state == "pressed" then
        r, g, b = 0.10, 0.10, 0.10
    elseif state == "hover" then
        r, g, b = 0.30, 0.30, 0.30
    elseif state == "active" then
        r, g, b = S.accent.r, S.accent.g, S.accent.b
    elseif state == "activeHover" then
        r = math.min(S.accent.r * 1.2, 1)
        g = math.min(S.accent.g * 1.2, 1)
        b = math.min(S.accent.b * 1.2, 1)
    end

    local L, M, R = TEX(BTN.l), TEX(BTN.m), TEX(BTN.r)
    if L and R then
        draw3(el, L, M, R, x, y, w, h, h, a, r, g, b)
        return
    end
    el:drawRect(x, y, w, h, a, r, g, b)
    el:drawRectBorder(x, y, w, h, 1, S.frame.r, S.frame.g, S.frame.b)
end

--- The state name for a row that can be on and can be hovered. One place, so
--- rows and buttons in different panels never disagree about what "on" looks
--- like.
function S.buttonState(on, hovered, pressed)
    if pressed then return "pressed" end
    if on then return hovered and "activeHover" or "active" end
    return hovered and "hover" or nil
end

--- A tick box the way the family draws one: a flat square that lights on hover,
--- with the Neat check inside, in the same green used for "this is selected".
--- Same recipe as IHM_NeatStyle.styleTickBox, so a tick here and a tick in
--- Hairstyler are visibly the same control.
function S.styleTickBox(tb)
    if not tb or tb.nwStyled then return end
    tb.nwStyled = true
    tb.background = false

    tb.render = function(box)
        local n = #box.options
        if n < 1 then return end
        local tick = TEX(ICON_TICK)
        local sz = box.boxSize or math.min(box.width, box.height)
        local spacing = 10                    -- ISTickBox's own UI_BORDER_SPACING
        local total = n * (box.itemHgt + spacing) - spacing
        local y = math.floor((box.height - total) / 2)
        local boxDY = math.floor((box.itemHgt - sz) / 2)
        local textDY = math.floor((box.itemHgt - box.fontHgt) / 2)
        local hovered = box:isMouseOver()

        for i, label in ipairs(box.options) do
            local disabled = box.disabledOptions[label] and true or false
            local active = (hovered and box.mouseOverOption == i and box.enable and not disabled)
                or (box.joypadFocused and box.joypadIndex == i)
            local a = disabled and 0.45 or 1.0
            local r, g, b = 0.18, 0.18, 0.19
            if active then r, g, b = 0.30, 0.30, 0.32 end

            local bg = TEX(BTN.bg)
            if bg then
                box:drawTextureScaled(bg, box.leftMargin, y + boxDY, sz, sz, a, r, g, b)
            else
                box:drawRect(box.leftMargin, y + boxDY, sz, sz, a, r, g, b)
            end
            local brd = TEX(BTN.border)
            if brd then
                box:drawTextureScaled(brd, box.leftMargin, y + boxDY, sz, sz, a, 0.4, 0.4, 0.4)
            end

            if box.selected[i] == true then
                local isz = math.max(4, math.floor(sz * 0.66))
                local off = math.floor((sz - isz) / 2)
                if tick then
                    box:drawTextureScaled(tick, box.leftMargin + off, y + boxDY + off,
                        isz, isz, a, S.selection.r, S.selection.g, S.selection.b)
                else
                    box:drawRect(box.leftMargin + off, y + boxDY + off, isz, isz,
                        a, S.selection.r, S.selection.g, S.selection.b)
                end
            end

            if label ~= "" then
                box:drawText(label, box.leftMargin + sz + box.textGap, y + textDY,
                    S.text.r, S.text.g, S.text.b, a, box.font)
            end
            y = y + box.itemHgt + spacing
        end
    end
end

function S.iconClose()
    return TEX(ICON_CLOSE)
end

return S
