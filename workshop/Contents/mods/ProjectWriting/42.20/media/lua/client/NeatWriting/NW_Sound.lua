--[[ ============================================================================
    NW_Sound - i rumori della carta.

    Sono tutti suoni che il gioco ha gia': aprire e chiudere un libro, sfogliare
    una pagina, posare un simbolo o un biglietto sulla mappa, cancellare un
    segno. Nessun file nostro, nessun peso in piu' nel pacchetto, e soprattutto
    lo stesso rumore che il giocatore associa gia' a quel gesto.

      OpenBook / CloseBook / PageFlipBook   scripts/generated/sounds/player/
      MapAddSymbol / MapAddNote /             sounds_player_literature.txt
      MapRemoveMarking                        sounds_player_mapping.txt

    MAI `playSound`. Quello e' un rumore del mondo: lo sentono gli altri e lo
    sentono gli zombi. Scrivere sul proprio diario non e' un evento del mondo,
    ed e' gia' successo in questa famiglia di mod che un suono d'interfaccia
    diventasse un richiamo.

    Fra gli altri due si sceglie in base alla pausa, e il perche' sta su S.play.

    E sempre in silenzio se qualcosa manca: un suono che non parte non e' un
    guasto che valga un errore nel log.
============================================================================ ]]--

if isServer() then return end

require "NeatWriting/NW_Focus"

NW_Sound = NW_Sound or {}
local S = NW_Sound

--- Due suoni identici nello stesso millisecondo diventano uno rimbombante:
--- succede quando un gesto ne fa partire due (posa il simbolo, e la posa
--- salva). Sotto questa soglia il secondo si perde.
local GAP_MS = 60
local last, lastAt = nil, 0

--- Fa il rumore, sul canale giusto.
---
--- DUE CANALI, E LA PAUSA DECIDE QUALE. `playSoundLocal` e' un suono del
--- personaggio: parte dalla sua posizione nel mondo. Quando il mondo lo abbiamo
--- fermato noi - ogni finestra di questa mod lo ferma - quel canale non
--- avanza, e il rumore non arriva mai. Da fuori sembrava che il suono ci fosse
--- solo premendo i tasti a schermo: quello che si sentiva era il clic
--- dell'ISButton, che e' un suono d'interfaccia e con la pausa non c'entra.
---
--- Percio': a mondo fermo si usa il canale dell'interfaccia, a mondo che gira
--- quello del personaggio. Uno solo dei due per volta, mai tutti e due, o il
--- rumore raddoppia dove funzionano entrambi.
--- Lo stesso rumore, dichiarato due volte: una per il mondo e una per
--- l'interfaccia.
---
--- Il banco d'interfaccia del gioco non ha una pagina che gira - ha clic
--- generici - quindi `playUISound("PageFlipBook")` non suonava niente: quel
--- nome sta in `category = Player`. I gemelli in `category = UI` li dichiara
--- la mod, in media/scripts/sounds_neatwriting.txt, e puntano agli stessi
--- eventi audio del gioco.
local UI_TWIN = {
    PageFlipBook     = "NW_PageFlip",
    OpenBook         = "NW_BookOpen",
    CloseBook        = "NW_BookClose",
    MapOpen          = "NW_MapOpen",
    MapClose         = "NW_MapClose",
    MapAddNote       = "NW_MapAddNote",
    MapAddSymbol     = "NW_MapAddSymbol",
    MapRemoveMarking = "NW_MapRemoveMarking",
}

function S.play(player, name)
    if not name then return end
    local p = player
    if not p and getSpecificPlayer then p = getSpecificPlayer(0) end

    local t = getTimestampMs and getTimestampMs() or 0
    if name == last and t - lastAt < GAP_MS then return end
    last, lastAt = name, t

    -- Fermo per mano nostra, non "c'e' una finestra aperta": con la pausa
    -- spenta dalle opzioni il mondo gira, e il canale del personaggio suona
    -- come suona sempre.
    local paused = NW_Focus and NW_Focus.paused and NW_Focus.paused()
    local twin = UI_TWIN[name]
    if paused and twin then
        pcall(function() getSoundManager():playUISound(twin) end)
    elseif p then
        pcall(function() p:playSoundLocal(name) end)
    end
end

function S.open(player)   S.play(player, "OpenBook") end
function S.close(player)  S.play(player, "CloseBook") end
function S.flip(player)   S.play(player, "PageFlipBook") end
function S.symbol(player) S.play(player, "MapAddSymbol") end
function S.note(player)   S.play(player, "MapAddNote") end
function S.erase(player)  S.play(player, "MapRemoveMarking") end
