--[[ ============================================================================
    NW_Focus - il mondo si ferma mentre si scrive.

    Solo si ferma: la pausa NON scurisce niente. Al banco era sembrato di si',
    ma quella prova stava dentro una finestra che copriva tutto lo schermo, e
    quello che si era scambiato per un oscuramento era la finestra stessa. Il
    velo lo disegna NW_Window:renderDim(); qui si ferma solo l'orologio.

    Il gioco rimette la velocita' per conto suo, quindi la pausa va riaffermata
    a ogni frame finche' la finestra e' aperta. Chiuderla e' quello che la toglie.

    Il conteggio serve perche' due finestre nostre possono sovrapporsi - una
    stampa aperta sopra un foglio - e la prima che si chiude non deve far
    ripartire il mondo sotto la seconda.

    LA PAUSA SI PUO' SPEGNERE (Opzioni > Mod). Allora le finestre si contano
    lo stesso ma l'orologio non si tocca, e chi scrive lo fa mentre il mondo
    gira: e' quello che serve in rete, dove fermare il proprio schermo non
    ferma niente a nessun altro, e dove essere interrotti mentre si scrive e'
    parte del gioco. F.paused() dice quale delle due si sta usando - lo
    chiedono il suono, che sceglie un canale, e chiunque debba sapere se
    un'azione a tempo partira' mai.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Config"

NW_Focus = NW_Focus or {}
local F = NW_Focus

F.holders = 0
F.readers = {}

--- Vero se il mondo lo abbiamo fermato NOI. E' una cosa diversa da "c'e' una
--- finestra aperta": chi spegne la pausa dalle opzioni tiene le finestre e si
--- tiene il mondo che gira, e chi deve scegliere un canale audio o decidere se
--- un'azione a tempo partira' mai deve sapere quale delle due.
F.stopped = false

local function speedControls()
    local ok, s = pcall(function() return UIManager.getSpeedControls() end)
    return ok and s or nil
end

--- Ferma il mondo. Da chiamare quando una finestra si apre.
---
--- Se la pausa e' spenta dalle opzioni la finestra si conta lo stesso - serve a
--- sapere che c'e' - ma l'orologio non si tocca.
function F.take()
    F.holders = F.holders + 1
    if F.holders > 1 then return end
    if not NW.pauseWhileWriting() then return end
    F.stopped = true
    pcall(function() UIManager.setShowPausedMessage(false) end)
    F.hold()
end

--- Riafferma la pausa. Va chiamata a ogni frame da chi tiene la finestra:
--- il gioco rimette la velocita' da solo e senza questo il mondo riparte.
function F.hold()
    if F.holders <= 0 or not F.stopped then return end
    local s = speedControls()
    if s then pcall(function() s:SetCurrentGameSpeed(0) end) end
end

--- Restituisce il mondo. Da chiamare quando una finestra si chiude.
function F.release()
    if F.holders <= 0 then return end
    F.holders = F.holders - 1
    if F.holders > 0 then return end
    if not F.stopped then return end
    F.stopped = false
    local s = speedControls()
    if s then pcall(function() s:SetCurrentGameSpeed(1) end) end
    pcall(function() UIManager.setShowPausedMessage(true) end)
end

--- Il mondo e' fermo per mano nostra?
function F.paused()
    return F.holders > 0 and F.stopped
end

--- Rida' il mondo senza chiudere niente: e' quello che serve quando la pausa
--- viene spenta dalle opzioni con una pagina gia' aperta. Le finestre restano
--- dove sono, l'orologio riparte, e nessuno lo riafferma piu' perche' F.hold
--- guarda F.stopped.
function F.thaw()
    if not F.stopped then return end
    F.stopped = false
    local s = speedControls()
    if s then pcall(function() s:SetCurrentGameSpeed(1) end) end
    pcall(function() UIManager.setShowPausedMessage(true) end)
end

-- ---------------------------------------------------------------------------
-- La modalita' lettura
-- ---------------------------------------------------------------------------
--
-- E' quella del gioco: la stessa che accende un libro aperto, e che il gioco
-- disegna da se'. Non ce la mettiamo noi, la si accende e basta.
--
-- LA ACCENDIAMO NOI PERCHE' NESSUN ALTRO PUO'. Sarebbe l'azione a tempo di
-- vanilla a farlo - ISWriteSomething:serverStart() chiama setReading(true) - ma
-- l'azione parte al primo tick del mondo, e noi il mondo lo abbiamo appena
-- fermato: a velocita' zero quel tick non arriva mai e lo start non gira. Da
-- fuori sembrava che la modalita' lettura non ci fosse; in realta' non era mai
-- cominciata.
--
-- Va spenta con la stessa cura con cui si spegne la pausa: un personaggio
-- lasciato "in lettura" non torna a fare altro.

local function setReading(player, on)
    if not player or not player.setReading then return end
    pcall(function() player:setReading(on and true or false) end)
end

--- Accende la lettura per questo giocatore. Ricordarsi chi si e' acceso serve a
--- non spegnere quello sbagliato quando due finestre si sovrappongono.
function F.read(player)
    if not player then return end
    for _, p in ipairs(F.readers) do if p == player then return end end
    F.readers[#F.readers + 1] = player
    setReading(player, true)
end

--- Spegne la lettura, se questa finestra era l'ultima ad averla accesa.
function F.unread(player)
    if not player then return end
    for i = #F.readers, 1, -1 do
        if F.readers[i] == player then table.remove(F.readers, i) end
    end
    for _, p in ipairs(F.readers) do if p == player then return end end
    setReading(player, false)
end

--- Rete di sicurezza: se una finestra muore senza chiamare release - il
--- giocatore muore, il gioco cambia stato - il mondo resterebbe fermo per
--- sempre. Un conteggio a zero forzato costa niente e non ha rimedio migliore.
function F.reset()
    for i = #F.readers, 1, -1 do
        setReading(F.readers[i], false)
        F.readers[i] = nil
    end
    if F.holders <= 0 then return end
    F.holders = 1
    F.release()
end

Events.OnGameStart.Add(function() F.holders = 0 F.stopped = false F.readers = {} end)

return NW_Focus
