--[[ ============================================================================
    NW_Context - "Scrivi qualcosa" apre la nostra finestra.

    Vanilla passa da una funzione sola:

        ISInventoryPaneContextMenu.onWriteSomething = function(notebook, editable, player)
            ... ISUIWriteJournal:new(0, 0, 350, height, ...)

    Un punto solo da sostituire, e riceve gia' tutto quello che serve: l'oggetto,
    se e' scrivibile o solo leggibile, e il giocatore.

    La sostituzione e' selettiva, ed e' importante che lo sia. Vanilla apre
    quella finestra su diciannove oggetti - quaderni, diari, fogli, schede,
    biglietti d'auguri. Noi ne copriamo otto, quelli su cui si scrive davvero, e
    per tutti gli altri la finestra del gioco resta quella giusta: NW_Layouts
    torna nil per quello che non e' nostro e la chiamata prosegue da vanilla.

    Cosi' la mod non toglie niente a nessuno mentre viene costruita: chi apre un
    biglietto di auguri continua a scriverci come prima.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISWriteSomething"
require "NeatWriting/NW_Layouts"
require "NeatWriting/NW_Doc"
require "NeatWriting/UI/NW_Window"

local previous = ISInventoryPaneContextMenu.onWriteSomething

--[[ LA PARTENZA DELL'AZIONE, SENZA LA FINESTRA DI VANILLA.

    Dalla 42.21 ISWriteSomething:start() costruisce lei il diario di vanilla
    (ISUIWriteJournal) con getSpecificPlayer(self.player). Noi l'azione la
    creavamo senza `player`, quindi getSpecificPlayer(nil) era nil e il diario
    esplodeva nel costruttore ("getPlayerNum of non-table", segnalazione del
    collaudo 42.21); e anche con `player` si sarebbe aperto il diario di vanilla
    sopra il nostro foglio.

    Si sostituisce start SULL'ISTANZA, non sulla classe: le altre scritture
    restano di vanilla, e in rete il server ricostruisce l'azione per nome
    (ISWriteSomething, che conosce) e chiama serverStart/complete, che qui non
    si toccano. Questa start fa quello che fa la sua, riga per riga, tranne
    creare la finestra: `modal` e' gia' la nostra, e stop/perform la chiudono
    con destroy() come chiudevano quella di vanilla.
]]
local function startWithOurWindow(self)
    if isClient() and self.item and self.container then
        self.item = self.container:getItemById(self.item:getID()) or self.item
    end
    if JoypadState.players[self.player + 1] and self.modal then
        setJoypadFocus(self.player, self.modal)
    end

    if self.item:getReadType() then
        self:setAnimVariable("ReadType", self.item:getReadType())
    elseif (self.item:getType() == "Newspaper" or self.item:hasTag(ItemTag.NEWSPAPER_READ)) then
        self:setAnimVariable("ReadType", "newspaper")
    elseif (self.item:hasTag(ItemTag.PICTURE)) then
        self:setAnimVariable("ReadType", "photo")
    else
        self:setAnimVariable("ReadType", "book")
    end
    self:setActionAnim(CharacterActionAnims.Read)
    self:setOverrideHandModels(nil, self.item)

    self.character:reportEvent("EventRead")

    if self:isBook(self.item) then
        self.character:playSound("OpenBook")
    else
        self.character:playSound("OpenMagazine")
    end
end

ISInventoryPaneContextMenu.onWriteSomething = function(notebook, editable, player)
    local playerObj = getSpecificPlayer(player)

    -- Un supporto che non conosciamo torna a vanilla senza che se ne accorga
    -- nessuno. Lo stesso vale se la finestra non si apre: meglio quella del
    -- gioco che nessuna.
    if NW_Layouts.forItem(notebook) and playerObj then
        local ok, win = pcall(NW_Window.open, notebook, playerObj, editable)
        if ok and win then
            -- L'azione a tempo e' quella di vanilla, e non e' un dettaglio: e'
            -- lei che fa sedere il personaggio a scrivere, che gli mette il
            -- quaderno in mano, che rifiuta se e' troppo buio per leggere e che
            -- interrompe tutto se il giocatore si mette a correre. La finestra
            -- le fa da `modal`, come il diario di vanilla, quindi ISWriteSomething
            -- la chiude da se' chiamandole destroy().
            local action = ISWriteSomething:new(playerObj, notebook)
            action.modal = win
            action.player = player
            action.editable = editable
            action.start = startWithOurWindow
            ISTimedActionQueue.add(action)
            return
        end
        if not ok then print("NW_Context: " .. tostring(win)) end
    end

    return previous(notebook, editable, player)
end

-- ---------------------------------------------------------------------------
-- "Non contiene niente di interessante", su un diario pieno
-- ---------------------------------------------------------------------------
--
-- LA SEGNALAZIONE: in partita ospitata, lei non riusciva piu' ad aprire il
-- diario su cui scriveva - la voce "Leggi Il mio diario" era rossa, con scritto
-- "Non contiene niente di interessante" - mentre lui lo apriva. Stessa cosa su
-- certi taccuini, a parti invertite. La giocatrice sospettava "It Is Of Interest
-- To Me", ma quella mod tocca solo biglietti, lettere, posta e documenti
-- (RegisterReadableItems.lua), non i diari.
--
-- IL MECCANISMO E' DI VANILLA, e sta in ISInventoryPaneContextMenu:
--
--     local editable = playerInv:containsTagRecurse(ItemTag.WRITE) or ... PEN ...
--     if lockedBy and lockedBy ~= username then editable = false end
--     if not editable then  -> "Leggi %1"   invece di "Scrivi %1"
--     ...
--     elseif not editable and item:isEmptyPages() then -> spenta, "niente di interessante"
--
-- Chi NON HA UNA PENNA ADDOSSO (o trova il quaderno chiuso a chiave da un altro)
-- si vede offrire "Leggi" invece di "Scrivi". E "Leggi" si spegne se le pagine
-- DI VANILLA sono vuote - ma su un quaderno scritto con questa mod l'inchiostro,
-- i simboli e le pagine in piu' stanno nella modData, e vanilla non le vede. Chi
-- aveva la penna in tasca apriva; chi l'aveva posata no. Da fuori sembrava un
-- difetto di certi oggetti e di certi giocatori, ed era un difetto di chi guarda
-- dentro il quaderno.
--
-- Qui la voce si riaccende quando il quaderno ha contenuto NOSTRO, e solo nel
-- caso di quella spiegazione: "troppo buio" e "analfabeta" restano spente,
-- perche' quelle vanilla le ha giuste.
local function onFillMenu(playerNum, context, items)
    local empty = getText("ContextMenu_EmptyNotebook")
    for _, entry in ipairs(items or {}) do
        local item = entry
        if type(entry) == "table" and entry.items then item = entry.items[1] end
        if item and instanceof(item, "InventoryItem") and NW_Layouts.forItem(item)
                and NW_Doc.hasContent(item) then
            local name
            pcall(function() name = getText("ContextMenu_Read_Note", item:getName()) end)
            local option = name and context:getOptionFromName(name)
            if option and option.notAvailable and option.toolTip
                    and option.toolTip.description == empty then
                option.notAvailable = false
                option.toolTip = nil
            end
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillMenu)
