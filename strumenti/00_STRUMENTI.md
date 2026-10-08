# Gli strumenti di Project Writing

Script `node`, tutti da lanciare **dalla radice dell'officina**
(`NEATUI/`), come gli strumenti di `COMUNE/strumenti/`. Su questa macchina non
c'è Lua né un Python utilizzabile: qui dentro non si trova altro che JavaScript.

```
strumenti/
  controlli/    rileggono il codice e i pixel della mod, e dicono se torna
  anteprime/    disegnano fuori dal gioco com'è fatta una schermata
  arte/         hanno prodotto le immagini che stanno in workshop/
  traduzioni/   generano i file delle 26 lingue
```

Le immagini che questi script producono finiscono in `art/anteprime/`; i
materiali grafici di partenza stanno in `art/sorgenti/`.

## controlli/

| script | cosa risponde |
|---|---|
| `scrivibili.js` | quali `CanBeWrite` di vanilla abbiamo coperto, e se ogni supporto nominato in `L.BY_ITEM` esiste davvero |
| `descrittore.js` | libreria: legge `NW_Layouts.lua` e restituisce i supporti veri, così nessuno strumento lavora su numeri copiati a mano |
| `misure-scrittura.js` | dove cade la scrittura su ogni foglio, e se il passo delle righe stampate si aggancia a quello della grafia |
| `prova-acapo.js` | il banco di prova dell'a capo automatico: `NW_Writer.layout` rifatto fuori dal gioco, su casi noti |
| `aree-pagine.js` | misura sulle immagini dove si può scrivere. **Fermo**: legge i prototipi da `PZ MODDING/Project Writing/canvas`, cartella che non esiste più. Serve solo se si aggiunge un supporto nuovo, e allora va ripuntato alle immagini in `workshop/` |
| `png.js` | libreria: leggere e scrivere PNG a mano, perché qui non c'è una libreria che lo faccia |
| ~~`chiavi.js`~~ | **spostato in `COMUNE/strumenti/chiavi.js`**: il difetto che trova - una schermata che mostra il nome grezzo di una chiave - non ha niente di Project Writing, e adesso vale per tutte le mod. La sigla (NW, NEQ, IHM, NeatXP) se la deduce da sola |
| ~~`oggetti.js`~~ | **spostato in `COMUNE/strumenti/oggetti.js`**, per la stessa ragione. Le tabelle e le costanti di nomi vanno ancora marcate `--@oggetti` |
| `peso-tratti.js` | quanto pesa un disegno a mano libera, e quanto manca al tetto di 2 MB del motore per gli oggetti del giocatore. Legge le costanti da `NW_Brush.lua`, ma l'algoritmo è una copia in JavaScript: se si tocca la matematica del pennello va toccata anche qui |

`scrivibili.js` è quello che si rilancia più spesso: va lanciato a ogni build
nuova del gioco, perché le voci scrivibili di vanilla possono cambiare.

## anteprime/

Ricalcano fuori dal gioco una schermata della mod, misura per misura, e ne
scrivono l'immagine. Servono a giudicare l'estetica senza avviare Project
Zomboid, e a vedere se una modifica alle misure fa quello che si crede.

`anteprima-pannello.js`, `anteprima-reading.js`, `anteprima-righe.js`,
`anteprima-scrittura.js`, `anteprima-setting.js`.

**Sono copie del layout, non il layout.** Quando `NW_Panel` cambia le sue
misure, l'anteprima resta indietro finché non la si aggiorna: dice come *era*
il pannello, non come è. Vale per tutte e cinque.

## arte/

Hanno prodotto quello che sta in `workshop/media/ui/NeatWriting/`, e si
rilanciano solo per rifare un pezzo:

`genera-icone.js` (le icone degli strumenti), `genera-frecce.js` (le due frecce
dello sfoglio), `genera-icona-mod.js` (`icon.png` e `poster.png`),
`estrai-icona.js` (tira fuori un'icona del gioco dai suoi `.pack`),
`scritta-mano.js` (una scritta nella grafia del gioco, come immagine),
`genera-icone-matita.js` (le due facce della matita, l'elicottero del "segui" e
il taccuino della trascrizione, da `art/sorgenti/icon/`),
`anteprima-slot.js` (le caselle degli strumenti composte come le compone il
motore, con i colori letti da `NW_Config.lua` e le icone vere del gioco in
`art/sorgenti/oggetti-gioco/`: esce `art/anteprime/anteprima-slot.png`. Si
rilancia ogni volta che si tocca un colore `slot` o `NW_Style.drawSlot`).

## traduzioni/

`genera.js` scrive i file di ognuna delle 26 lingue dentro `workshop/`
(`IG_UI`, `UI` e, per le chiavi `Sandbox_*` delle opzioni sandbox, `Sandbox`:
ognuno in `.json` e `.txt`), leggendo i vocabolari (`voc-interfaccia.js`, `voc-simboli-*.js`),
l'elenco delle lingue (`lingue.js`) e la mappa dei simboli
(`mappa-simboli.js`). `schede.js` controlla che nessuna scheda della tavola
resti con troppe poche tessere.

Il controllo che conta davvero sulle traduzioni sta però nell'officina:
`node COMUNE/strumenti/traduzioni.js` verifica che le 26 lingue abbiano le chiavi
dell'inglese, che il `.json` e il `.txt` combacino e che nessuna frase abbia un
`%` fuori posto. Dopo una riscrittura automatica si passa su **tutti** i file,
non su un campione (lezione 51).
