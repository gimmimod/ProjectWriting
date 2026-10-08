--[[ ============================================================================
    NW_DarkMap - la mappa del mondo in notturna.

    UN VELO, NON VENTI STRATI RIFATTI. La mod di riferimento (Darker Map, di
    Lightja) fa `styleAPI:clear()` e poi ridichiara ogni strato di vanilla -
    foreste, acqua, cinque tipi di strada, otto tipi di edificio - moltiplicando
    ogni colore per un fattore. Funziona, e ha due difetti che si pagano dopo:
    quella lista e' una COPIA di `MapUtils.initDefaultStyleV3`, quindi invecchia
    in silenzio a ogni build che aggiunge o cambia uno strato; e non si puo'
    accendere e spegnere con una transizione, perche' l'unico modo di cambiare
    intensita' e' rifare tutto da capo.

    Qui vanilla costruisce il suo stile come sempre, e noi aggiungiamo UN solo
    strato sopra: una texture bianca stesa su tutta la mappa, tinta di scuro.
    E' la stessa ricetta di `MapUtils.overlayPaper`, che e' come vanilla mette
    la grana della carta - stesso `newTextureLayer`, stesso `setUseWorldBounds`.
    Niente da tenere allineato, e il giorno che il gioco aggiunge un tipo di
    edificio quello diventa scuro insieme al resto senza che noi si sappia che
    esiste.

    IL PASSAGGIO E' FLUIDO PERCHE' NON PASSA DA LI'. Cambiare lo stile e'
    istantaneo per forza: si ridisegna il fotogramma dopo. La morbidezza la
    mette un velo disegnato SULL'INTERFACCIA (NW_DarkMap.veil), che sale a
    coprire, lascia avvenire il cambio quando e' opaco, e poi si ritira. Chi
    guarda vede una dissolvenza; il cambio vero e' nascosto nel suo punto piu'
    buio.

    I SEGNI SI SCHIARISCONO, e viene dal riferimento: la matita scrive quasi
    nero, e su una mappa notturna un segno quasi nero non si vede. Qui pero il
    colore si alza mentre esce dal pennello (NW_DarkMap.lift) e non nella
    tavolozza, cosi la regola vale allo stesso modo per i tratti di stasera e
    per quelli riletti da una partita di un mese fa.

    BIGLIETTI E SIMBOLI PASSANO DA UN'ALTRA PORTA. Quelli non li disegniamo noi,
    li disegna il motore leggendo il colore scritto dentro al simbolo, e in Lua
    non c'e' nessun punto in mezzo dove schiarirlo al volo: si cambia il colore
    del simbolo e lo si rimette com'era. Il come sta piu' sotto, in tintPass.

    E LA NOTTE PUO' ACCENDERSI DA SOLA, se glielo si lascia fare: dalle 22 alle
    6, le ore in cui fuori una mappa non si legge senza una torcia.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Config"

NW_DarkMap = NW_DarkMap or {}
local D = NW_DarkMap

--- Quanto scurisce, e di che colore.
---
--- Non nero puro: un blu molto scuro. Il nero spegne anche la differenza fra
--- una strada e un prato - resta una macchia sola - mentre una dominante fredda
--- lascia leggere le forme e somiglia a una mappa guardata di notte.
local TINT = { r = 18, g = 22, b = 38 }
local ALPHA = 175          -- su 255
local LAYER = "nwDarkMap"

--- Quanto dura la dissolvenza, e quando in mezzo avviene il cambio.
local FADE_MS = 260

-- ---------------------------------------------------------------------------
-- Lo stato
-- ---------------------------------------------------------------------------

local fadeFrom = nil       -- momento in cui e' cominciata la dissolvenza

function D.isOn() return NW.darkMap() end

-- ---------------------------------------------------------------------------
-- Lo strato
-- ---------------------------------------------------------------------------

local function apiOf(mapUI)
    local api
    pcall(function() api = mapUI.javaObject:getAPIv1() end)
    return api
end

--- Stende (o toglie) il velo scuro sulla mappa.
---
--- Lo stile si rifa' da zero tutte e due le volte, e non e' spreco: `styleAPI`
--- non offre un modo di togliere un singolo strato, e ricostruire e' quello che
--- fa vanilla stessa a ogni apertura di mappa. Succede a un cambio di
--- interruttore, non a ogni fotogramma.
function D.apply(mapUI)
    if not mapUI then return false end
    local api = apiOf(mapUI)
    if not api then return false end

    local styleAPI
    pcall(function() styleAPI = api:getStyleAPI() end)
    if not styleAPI then return false end

    -- PRIMA LO STILE DI VANILLA, INTERO E NON NOSTRO - e intero vuol dire
    -- tutte e due le righe. La mappa del mondo si veste sempre in due tempi,
    -- initDefaultStyleV3 e poi overlayPaper, e vanilla le chiama in coppia in
    -- ognuno dei quattro punti in cui rifa lo stile. Chiamando solo la prima
    -- la mappa perdeva la grana della carta - e non la riprendeva tornando al
    -- giorno, perche di li in poi nessuno la rimette piu.
    --
    -- E se il giocatore sta guardando la mappa satellitare, quello e lo stile
    -- da rimettere: ricostruire la carta gli spegnerebbe sotto le mani una
    -- cosa che aveva acceso lui.
    local ok = pcall(function()
        if mapUI.isTerrainImage and mapUI.showTerrainImage then
            mapUI:showTerrainImage()   -- fa il suo clear() da se
        else
            MapUtils.initDefaultStyleV3(mapUI)   -- fa il suo clear() da se
            MapUtils.overlayPaper(mapUI)
        end
    end)
    if not ok then return false end

    if not D.isOn() then
        -- Di giorno finisce qui, e non si rimette a mano nemmeno il colore del
        -- fondo: initDefaultStyleV1 ha gia scritto i suoi tre (219,215,192, il
        -- colore della carta) insieme a quelli delle zone mai viste. Scriverne
        -- altri qui voleva dire inventare un grigio al posto della sua carta.
        mapUI.nwDark = false
        D.tintSymbols(mapUI)
        return true
    end

    pcall(function()
        -- Il fondo oltre i bordi della mappa e le zone mai viste: se restassero
        -- chiari il velo sembrerebbe una toppa appoggiata su un foglio bianco.
        api:setBackgroundRGBA(TINT.r / 255 * 0.35, TINT.g / 255 * 0.35,
            TINT.b / 255 * 0.35, 1.0)
        api:setUnvisitedRGBA(TINT.r / 255 * 0.5, TINT.g / 255 * 0.5,
            TINT.b / 255 * 0.5, 1.0)
        -- La griglia delle zone non viste, chiara e quasi invisibile: quella
        -- scura di vanilla su fondo scuro diventa un reticolo nero. E' la stessa
        -- correzione che Darker Map annota nel suo commento.
        api:setUnvisitedGridRGBA(1, 1, 1, 0.03)

        local layer = styleAPI:newTextureLayer(LAYER)
        layer:setMinZoom(0.00)
        layer:setBoundsInSquares(api:getMinXInSquares(), api:getMinYInSquares(),
            api:getMaxXInSquares() + 1, api:getMaxYInSquares() + 1)
        layer:setUseWorldBounds(true)
        layer:addFill(0.00, TINT.r, TINT.g, TINT.b, ALPHA)
        layer:addTexture(0.00, "media/white.png")
        -- Il cartello appeso alla mappa: e il modo che ha D.lift di sapere se il
        -- foglio sotto i tratti e davvero notturno. Ultima riga dentro il pcall,
        -- non fuori: se lo strato non e riuscito a nascere la mappa e rimasta
        -- chiara, e schiarire l inchiostro su una mappa chiara lo cancella.
        mapUI.nwDark = true
    end)
    -- Fuori dal pcall, e legge `nwDark`: i simboli si mettono d'accordo con
    -- quello che la mappa e' diventata davvero, non con quello che si voleva.
    D.tintSymbols(mapUI)
    return true
end

-- ---------------------------------------------------------------------------
-- Il pennello, che deve restare visibile
-- ---------------------------------------------------------------------------

--- Schiarisce un colore quanto basta a leggerlo sul buio. Di giorno, e su una
--- superficie che notturna non e, restituisce quello che ha ricevuto.
---
--- CHIEDE ALLA MAPPA, NON ALLA PREFERENZA. La notte si accende solo sulla mappa
--- del mondo: una mappa di carta resta color carta anche con la luna accesa, e
--- schiarirle sopra i segni li avrebbe slavati su un fondo chiaro. Il cartello
--- lo appende D.apply alla mappa che ha davvero vestito.
---
--- SI FA QUI, AL MOMENTO DI DISEGNARE, E NON NELLA TAVOLOZZA. Il primo tentativo
--- alzava il colore dentro NW.INKS: funzionava per i tratti riletti dal
--- deposito - che tengono solo il nome dell inchiostro e ne ricavano il colore
--- ogni volta - e non per quelli disegnati nella sessione, che il colore se lo
--- portano dentro da quando sono nati. Meta dei segni si schiariva e meta no, e
--- la meta sbagliata cambiava a ogni ricarica della partita. Toccando invece il
--- colore mentre esce, la regola vale per tutti alla stessa maniera: i propri, i
--- tratti degli altri, quelli di ieri.
---
--- Alza la LUMINOSITA lasciando stare il rapporto fra i canali, invece di
--- impastare col bianco: un rosso schiarito verso il bianco diventa rosa e non e
--- piu il rosso che chi ha disegnato aveva scelto, mentre moltiplicato resta
--- rosso e diventa solo piu acceso.
---
--- E' UN PAVIMENTO, NON UN LIVELLO UNICO. La prima versione portava tutto quello
--- che era piu' scuro a una luminosita' fissa: leggibile, ma due colori diversi
--- sullo stesso raggio - il nero 0.1 e il grigio 0.4 - uscivano identici. Per i
--- tratti non cambiava niente; per i simboli si', perche' li' il colore
--- schiarito va poi RIMESSO com'era, e di due colori diventati uno non si sa
--- piu' quale rimettere. Con un pavimento l'ordine si conserva: piu' scuro
--- entra, piu' scuro esce, e nessun colore ne raggiunge un altro. 0.50 e'
--- scelto perche' lascia il nero dove stava prima (0.55), che e' il punto in cui
--- si legge bene sul velo notturno.
local FLOOR = 0.50

--- E QUANDO MOLTIPLICARE NON BASTA, IL RESTO LO METTE IL BIANCO. Un blu pieno
--- (0,0,1) ha una luminosita' di 0.11 e nessun fattore la alza: il canale e' gia'
--- al massimo, e moltiplicare non fa altro che sbattere contro il tetto. Cosi'
--- l'inchiostro blu restava scuro sul buio per quanto lo si moltiplicasse.
--- Prima si alza per moltiplicazione, che e' l'unica strada che non cambia il
--- colore; solo quello che manca si prende impastando col bianco, e si impasta
--- il minimo indispensabile.
local function liftRGB(r, g, b)
    local function lumOf(x, y, z) return 0.30 * x + 0.59 * y + 0.11 * z end
    local lum = lumOf(r, g, b)
    local want = FLOOR + lum * (1 - FLOOR)
    if want <= lum then return r, g, b end

    if lum > 0.001 then
        local k = want / lum
        r, g, b = math.min(1, r * k), math.min(1, g * k), math.min(1, b * k)
        lum = lumOf(r, g, b)
    end
    if lum >= want or lum >= 0.999 then return r, g, b end

    local t = (want - lum) / (1 - lum)
    return r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t
end

function D.lift(r, g, b, ui)
    if not (ui and ui.nwDark) then return r, g, b end
    return liftRGB(r, g, b)
end

-- ---------------------------------------------------------------------------
-- Biglietti e simboli, che dal pennello non passano
-- ---------------------------------------------------------------------------
--
-- I tratti a mano libera li disegniamo noi, un segmento alla volta, e il colore
-- si schiarisce mentre esce. Biglietti e simboli no: quelli li disegna il
-- motore, dalla sua lista, e in Lua non c'e' nessun punto in mezzo dove
-- infilarsi. L'unico colore che il motore guarda e' quello scritto NEL simbolo.
--
-- Quindi lo si cambia - e lo si rimette. Il colore vero non va perso per
-- strada, perche' quello e' il colore che il gioco salva: si tiene da parte, e
-- a ogni passata si guarda se il simbolo porta ancora addosso il colore che ci
-- abbiamo messo noi. Se ne porta un altro vuol dire che qualcuno l'ha ridipinto
-- nel frattempo, e allora il vero e' quello nuovo: non si sovrascrive mai la
-- scelta di chi guarda.
--
-- Si rimette com'era chiudendo la mappa (NW_Map), che e' l'unico momento in cui
-- si e' sicuri che dopo non si disegna piu' - e prima che una partita salvata
-- porti via il colore della notte credendolo quello vero.

local function symbolsOf(mapUI)
    local sapi
    pcall(function() sapi = mapUI and mapUI.symbolsUI and mapUI.symbolsUI.symbolsAPI end)
    return sapi
end

--- Un simbolo col SUO colore addosso, non uno che lo eredita.
---
--- Biglietti e simboli posati da qualcuno - dai nostri strumenti come da quelli
--- di vanilla - ricevono sempre un setRGBA, quindi passano tutti di qui. Quelli
--- che un colore proprio non ce l'hanno sono i nomi dei luoghi disegnati sulla
--- mappa, che il colore lo prendono dallo strato: dargliene uno vorrebbe dire
--- inventare il colore che avevano prima, e poi rimettere quello inventato.
--- Restano scuri di notte, e restano com'erano.
local function hasOwnColor(sym)
    local ok, res = pcall(function() return sym:hasCustomColor() end)
    if ok and res ~= nil then return res and true or false end
    return true   -- il metodo non c'e': si fa come si e' sempre fatto
end

--- Un colore ridotto a una parola, per poterlo usare come chiave.
local function keyOf(r, g, b)
    return math.floor(r * 255 + 0.5) .. "," .. math.floor(g * 255 + 0.5)
        .. "," .. math.floor(b * 255 + 0.5)
end

-- ---------------------------------------------------------------------------
-- La rete di sicurezza: un colore che riconosciamo come nostro
-- ---------------------------------------------------------------------------
--
-- Il ricordo di cosa c'era prima vive in memoria, e in memoria le cose si
-- perdono: una partita che si chiude male, un pannello ricostruito, un caso che
-- non abbiamo previsto. Se si perde quello, un biglietto resta del colore della
-- notte per sempre - e non c'e' modo di rimediare a mano, perche' il colore
-- vero non lo sa piu' nessuno.
--
-- Tranne in un caso, che poi e' quasi sempre: se il colore che il biglietto
-- porta addosso e' ESATTAMENTE quello che il nostro schiarimento produce da uno
-- dei nostri inchiostri, allora da li' veniva. Lo schiarimento e' una funzione
-- fissa e i nostri inchiostri sono cinque: i loro schiariti si calcolano una
-- volta e si riconoscono a vista. Due giri, perche' un colore schiarito due
-- volte e' quello che lascia dietro un ricordo perso a meta'.
--
-- E' una guardia stretta, non un indovinello: si corregge solo un colore che
-- combacia al millesimo con uno dei dieci, non uno che gli somiglia.

local GIRI = 2
local TOLL = 0.006      -- un colore passa da 8 bit e torna: si perde questo

local rescue = nil

local function buildRescue()
    rescue = {}
    for _, ink in ipairs(NW.INKS or {}) do
        local r, g, b = ink.r, ink.g, ink.b
        for _ = 1, GIRI do
            r, g, b = liftRGB(r, g, b)
            rescue[#rescue + 1] = { r, g, b, ink.r, ink.g, ink.b }
        end
    end
end

--- L'inchiostro da cui questo colore e' stato schiarito, se e' uno dei nostri.
local function unlift(r, g, b)
    if not rescue then buildRescue() end
    for _, e in ipairs(rescue) do
        if math.abs(r - e[1]) < TOLL and math.abs(g - e[2]) < TOLL
                and math.abs(b - e[3]) < TOLL then
            return { e[4], e[5], e[6] }
        end
    end
    return nil
end

--- Una passata su tutti i simboli: `dark` dice se vestirli per la notte o
--- rimetterli come li ha lasciati chi li ha scritti.
---
--- IL RICORDO E' UN COLORE, NON UN POSTO NELLA FILA. La prima versione teneva
--- l'appunto accanto al numero d'ordine del simbolo, e bastava cancellarne uno
--- in mezzo per far scalare tutti gli altri di uno: da li' in poi ogni appunto
--- guardava il simbolo sbagliato, e un colore gia' schiarito veniva schiarito
--- di nuovo. Siccome pero' il modo di schiarire e' ORDINATO - a colori diversi
--- corrispondono risultati diversi, ed e' per questo che ha un pavimento invece
--- di un livello unico - il colore schiarito basta da solo a dire da quale
--- veniva. La fila puo' cambiare quanto vuole.
local function tintPass(mapUI, dark)
    local sapi = symbolsOf(mapUI)
    if not sapi then return end
    local prima = mapUI.nwSymTint    -- colore messo da noi -> colore vero
    local dopo = {}

    pcall(function()
        local n = sapi:getSymbolCount()
        for i = 1, n do
            local sym = sapi:getSymbolByIndex(i - 1)
            if hasOwnColor(sym) then
                local cr, cg, cb = sym:getRed(), sym:getGreen(), sym:getBlue()
                local chiave = keyOf(cr, cg, cb)
                local nostro = prima and prima[chiave]
                local vero = nostro or { cr, cg, cb }
                -- La rete di sicurezza, prima di ogni altra cosa: se quello che
                -- crediamo il colore vero e' a sua volta un nostro schiarito,
                -- vero non e'. Vale in tutte e due le direzioni, quindi un
                -- biglietto rimasto acceso da un giro precedente si rimette a
                -- posto da solo alla prima passata.
                vero = unlift(vero[1], vero[2], vero[3]) or vero
                if dark then
                    local r, g, b = liftRGB(vero[1], vero[2], vero[3])
                    if keyOf(r, g, b) ~= chiave then
                        sym:setRGBA(r, g, b, sym:getAlpha())
                    end
                    -- LA CHIAVE E' QUELLO CHE IL MOTORE HA, non quello che gli
                    -- abbiamo dato. Un colore scritto in virgola mobile torna
                    -- indietro passato per otto bit, e per meno di un
                    -- duecentocinquantacinquesimo la chiave che ci saremmo
                    -- calcolati qui non sarebbe piu' stata la sua: alla passata
                    -- dopo il biglietto non risultava piu' nostro, il colore
                    -- vero si perdeva, e tornando al giorno restava acceso.
                    dopo[keyOf(sym:getRed(), sym:getGreen(), sym:getBlue())] = vero
                elseif keyOf(vero[1], vero[2], vero[3]) ~= chiave then
                    -- Si scrive solo dove sappiamo un colore vero DIVERSO da
                    -- quello che c'e': o perche' ce lo siamo appuntati, o perche'
                    -- la rete di sicurezza l'ha riconosciuto. Tutto il resto
                    -- l'ha scelto qualcuno dopo di noi, e non si tocca.
                    sym:setRGBA(vero[1], vero[2], vero[3], sym:getAlpha())
                end
            end
        end
        mapUI.nwSymCount = n
    end)

    mapUI.nwSymTint = dark and dopo or nil
end

--- Rimette i simboli al passo con la mappa che hanno sotto.
function D.tintSymbols(mapUI)
    if not mapUI then return end
    tintPass(mapUI, mapUI.nwDark and true or false)
end

--- Restituisce a tutti il loro colore vero. Da chiamare chiudendo la mappa.
---
--- Gira anche quando non risulta che si sia schiarito niente: e' il momento in
--- cui la rete di sicurezza serve di piu', perche' un ricordo perso e' proprio
--- il caso in cui "non risulta".
function D.untint(mapUI)
    if not mapUI then return end
    tintPass(mapUI, false)
end

--- Il colore vero di un simbolo, per chi lo deve copiare: di notte quello
--- scritto dentro e' il nostro, e una mappa ricopiata al buio si sarebbe
--- portata dietro i colori della notte.
function D.trueColor(mapUI, r, g, b)
    local nota = mapUI and mapUI.nwSymTint and mapUI.nwSymTint[keyOf(r, g, b)]
    if nota then return nota[1], nota[2], nota[3] end
    return r, g, b
end

-- ---------------------------------------------------------------------------
-- La notte del mondo, se si vuole che comandi lei
-- ---------------------------------------------------------------------------
--
-- Dalle 22 alle 6: le stesse ore in cui fuori non si legge piu' una mappa senza
-- una torcia. E' un'opzione perche' non tutti la vogliono - chi apre la mappa
-- per lavorarci sopra la vuole leggibile a qualunque ora - e perche' accesa
-- toglie un gesto invece di aggiungerne uno.
--
-- COMANDA AI PASSAGGI, NON DI CONTINUO. Guarda l'ora a ogni fotogramma ma agisce
-- solo quando il mondo passa da giorno a notte o viceversa: cosi' l'interruttore
-- a mano continua a funzionare, e quello che si sceglie resta scelto fino
-- all'alba successiva, invece di essere rimesso a posto un fotogramma dopo.

local NIGHT_FROM, NIGHT_TO = 22, 6

function D.isNight()
    local h
    pcall(function() h = getGameTime():getTimeOfDay() end)
    if not h then return false end
    return h >= NIGHT_FROM or h < NIGHT_TO
end

--- Il passaggio d'ora, se qualcuno l'ha delegato all'orologio.
local function autoTick(mapUI)
    if not NW.darkAuto() then D.wasNight = nil return end
    local night = D.isNight()
    if night == D.wasNight then return end
    D.wasNight = night
    if night ~= D.isOn() then D.toggle(mapUI) end
end

-- ---------------------------------------------------------------------------
-- L'interruttore, con la dissolvenza
-- ---------------------------------------------------------------------------

--- Accende o spegne. Il cambio vero avviene a meta' dissolvenza, quando il velo
--- e' opaco: da fuori si vede una schermata che si scurisce e si riapre gia'
--- cambiata, invece di un lampo.
function D.toggle(mapUI)
    NW.setDarkMap(not D.isOn())
    fadeFrom = getTimestampMs and getTimestampMs() or 0
    D.pending = mapUI
    return D.isOn()
end

--- Quanto e' opaco il velo adesso, da 0 a 1. Zero quando non c'e' nessuna
--- dissolvenza in corso.
---
--- Sale a uno a meta' strada e ridiscende: e' una V rovesciata, e il vertice e'
--- il momento in cui si puo' cambiare lo stile senza che si veda.
function D.veil()
    if not fadeFrom then return 0 end
    local now = getTimestampMs and getTimestampMs() or 0
    local t = (now - fadeFrom) / FADE_MS
    if t >= 1 then
        fadeFrom = nil
        return 0
    end
    if t < 0.5 then return t * 2 end

    -- Superata la meta': il cambio si fa adesso, una volta sola.
    if D.pending then
        D.apply(D.pending)
        D.pending = nil
    end
    return (1 - t) * 2
end

--- Da chiamare quando la mappa si apre: rimette lo stato scelto senza
--- dissolvenza, perche' non c'e' niente da cui dissolvere.
---
--- Se l'ora comanda, comanda gia' da qui: una mappa aperta all'una di notte si
--- apre scura, non chiara in attesa del passaggio delle 22 che e' gia' passato.
function D.restore(mapUI)
    if NW.darkAuto() then
        D.wasNight = D.isNight()
        if D.wasNight ~= D.isOn() then NW.setDarkMap(D.wasNight) end
    end
    D.apply(mapUI)
end

--- Una volta per fotogramma, dalla mappa aperta. Costa una domanda all'orologio
--- e una al conto dei simboli.
---
--- Il conto e' il modo di accorgersi che ne e' nato uno nuovo: un biglietto
--- appena scritto porta il colore vero, e senza questo resterebbe scuro fino al
--- prossimo colpo d'interruttore.
function D.watch(mapUI)
    if not mapUI then return end
    autoTick(mapUI)
    if not mapUI.nwDark then return end
    local sapi = symbolsOf(mapUI)
    if not sapi then return end
    local n
    pcall(function() n = sapi:getSymbolCount() end)
    if n and n ~= mapUI.nwSymCount then D.tintSymbols(mapUI) end
end

return NW_DarkMap
