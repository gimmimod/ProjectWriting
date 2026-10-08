--[[ ============================================================================
    NW_Transcript - la trascrizione di una stampa, accanto al foglio.

    VANILLA CE L'AVEVA E L'AVEVAMO TOLTA. Nella finestra di lettura del gioco un
    taccuino in basso stende sopra la carta il testo della stampa in chiaro:
    serve a chi gioca in un'altra lingua, perche' la carta resta disegnata in
    inglese e la trascrizione no, e a chi non riesce a leggere un volantino
    scritto piccolo. Il nostro NW_Reading lo aveva spento insieme al resto della
    striscia di tasti - "un muro di testo sopra la carta" - e con lui se ne era
    andato l'unico modo di leggere un giornale tradotto. La segnalazione diceva
    esattamente questo.

    ADESSO E' UN PANNELLO DELLA FAMIGLIA, NON UN VELO. Il testo non copre piu' la
    carta: sta in una finestra sua accanto alla cornice, con l'header di casa, e
    si legge insieme al foglio invece che al suo posto. Il testo e' quello che
    vanilla stessa mostra (`textTitle`, `textData` della finestra PrintMedia), non
    una copia nostra: la traduzione la fa il gioco.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISRichTextPanel"
require "NeatWriting/NW_Config"
require "NeatWriting/NW_Style"
require "NeatWriting/UI/NW_Tooltip"

NW_Transcript = ISPanel:derive("NW_Transcript")

local FONT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local HEADER_H = math.floor(FONT_MEDIUM * 1.5)
local PAD = 8
local WIDTH = 380
local GAP = 8           -- fra la cornice di lettura e questo pannello

--- Il testo di vanilla, nella forma che ISRichTextPanel sa impaginare: gli a capo
--- diventano <LINE>, e le parentesi angolate si neutralizzano perche' in un
--- pannello di testo ricco aprono un comando.
local function rich(text)
    text = tostring(text or "")
    text = text:gsub("\\n", "\n"):gsub("<", "("):gsub(">", ")")
    return (text:gsub("\r?\n", " <LINE> "))
end

function NW_Transcript:createChildren()
    local btn = NW_Style.headerButtonSize(HEADER_H)
    self.closeBtn = NW_Style.newSquareButton(0, 0, btn, NW_Style.iconClose(),
        self, NW_Transcript.close, NW_Style.close)
    self:addChild(self.closeBtn)
    NW_Tooltip.attach(self.closeBtn, getText("UI_Close"))

    local body = ISRichTextPanel:new(PAD, HEADER_H + PAD,
        self.width - PAD * 2, self.height - HEADER_H - PAD * 2)
    body:initialise()
    body:instantiate()
    body.background = false
    body.autosetheight = false
    body.clip = true
    body.defaultFont = UIFont.Medium
    body:setMargins(6, 4, 14, 4)
    body:addScrollBars()
    body.vscroll.background = false
    body.text = rich(self.textData)
    body:paginate()
    self:addChild(body)
    self.body = body

    self:layout()
end

--- Le misure dei figli dopo ogni cambio di altezza: segue la cornice.
function NW_Transcript:layout()
    local btn = NW_Style.headerButtonSize(HEADER_H)
    self.closeBtn:setX(self.width - btn - NW_Style.headerPadding(HEADER_H))
    self.closeBtn:setY(math.floor((HEADER_H - btn) / 2))
    if self.body then
        local h = math.max(40, self.height - HEADER_H - PAD * 2)
        if self.body:getHeight() ~= h then
            self.body:setHeight(h)
            if self.body.vscroll then self.body.vscroll:setHeight(h) end
            self.body:paginate()
        end
    end
end

function NW_Transcript:prerender()
    NW_Style.drawWindow(self, 0, 0, self.width, self.height, HEADER_H)
end

function NW_Transcript:render()
    local pad = NW_Style.headerPadding(HEADER_H)
    local iconSize = NW_Style.headerIconSize(HEADER_H)
    -- La "i" del tasto che l'ha aperta: la rivista e' del foglio, questa e' del testo.
    local icon = NW_Style.tex(NW.ICONS .. "Info.png")
    local tx = pad
    if icon then
        self:drawTextureScaled(icon, pad, math.floor((HEADER_H - iconSize) / 2),
            iconSize, iconSize, 1, NW_Style.text.r, NW_Style.text.g, NW_Style.text.b)
        tx = pad + iconSize + NW_Style.headerGap(HEADER_H)
    end
    -- Il titolo si accorcia prima della X, come in ogni header della famiglia.
    local title = self.title or ""
    local room = self.closeBtn:getX() - NW_Style.headerGap(HEADER_H) - tx
    local tm = getTextManager()
    if room > 0 and tm:MeasureStringX(UIFont.Medium, title) > room then
        while #title > 1 and tm:MeasureStringX(UIFont.Medium, title .. "...") > room do
            title = title:sub(1, #title - 1)
        end
        title = title .. "..."
    end
    self:drawText(title, tx, math.floor((HEADER_H - FONT_MEDIUM) / 2),
        NW_Style.text.r, NW_Style.text.g, NW_Style.text.b, 1, UIFont.Medium)
end

--- Accanto alla cornice: a destra se c'e' posto, altrimenti a sinistra, alto
--- quanto lei. Si rifa' a ogni frame dalla cornice, che si puo' spostare e
--- ridimensionare.
function NW_Transcript:follow(frame)
    local sw = getCore():getScreenWidth()
    local x = frame:getX() + frame:getWidth() + GAP
    if x + self.width > sw then
        x = math.max(0, frame:getX() - GAP - self.width)
    end
    if self:getX() ~= x then self:setX(x) end
    if self:getY() ~= frame:getY() then self:setY(frame:getY()) end
    if self.height ~= frame:getHeight() then
        self:setHeight(frame:getHeight())
        self:layout()
    end
end

function NW_Transcript:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if NW_Transcript.instance == self then NW_Transcript.instance = nil end
end

function NW_Transcript:onMouseDown() return true end
function NW_Transcript:onMouseUp() return true end

function NW_Transcript:new(title, textData, height)
    local o = ISPanel.new(self, 0, 0, WIDTH, height or 400)
    o.background = false
    o.moveWithMouse = false
    o.title = title or ""
    o.textData = textData or ""
    return o
end

--- Apre (o chiude, se e' gia' aperta) la trascrizione per una cornice.
function NW_Transcript.toggle(frame, title, textData)
    if NW_Transcript.instance then
        NW_Transcript.instance:close()
        return nil
    end
    local t = NW_Transcript:new(title, textData, frame:getHeight())
    t:initialise()
    t:instantiate()
    t:addToUIManager()
    t:setAlwaysOnTop(true)
    t:follow(frame)
    NW_Transcript.instance = t
    return t
end

--- C'e' una trascrizione da mostrare? Molte stampe hanno solo il disegno.
function NW_Transcript.available(textData)
    return type(textData) == "string" and textData:gsub("%s", "") ~= ""
end

return NW_Transcript
