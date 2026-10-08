/*  genera-icone-share.js - le tre icone della 2.0, alla misura di casa.
 *
 *  Arrivano da art/sorgenti/icon/ a 1254x1254 e circa 400 KB
 *  l'una: dentro il pacchetto ci vanno a 128x128, come Pen.png, Symbols.png e
 *  tutte le altre.
 *
 *      worldmap.png       -> WorldMap.png       "portami li' sulla mappa"
 *      createmapnote.png  -> CreateMapNote.png  ritaglia una mappa annotata
 *      share.png          -> Share.png          apre il pannello di condivisione
 *
 *  Il rimpicciolimento e' a media di scatola: ogni pixel di destinazione e' la
 *  media dei pixel di partenza che gli cadono sotto. Su un disegno al tratto
 *  come questi e' quello che conserva meglio i bordi, e su una riduzione di
 *  dieci volte prendere un pixel ogni dieci - il modo veloce - lascerebbe i
 *  contorni a scaletta.
 *
 *  La media si fa in alfa PREMOLTIPLICATO. Senza, i pixel trasparenti - che
 *  sono neri, ma nessuno li vede - tirano il colore del bordo verso il nero, e
 *  attorno alla figura resta un alone scuro. E' l'errore classico di chi
 *  rimpicciolisce un PNG con la trasparenza.
 *
 *      node MOD/ProjectWriting/strumenti/arte/genera-icone-share.js
 */
const fs = require('fs');
const path = require('path');
const { readPNG, writePNG } = require('../controlli/png.js');

// Le sorgenti stanno con l'arte della mod, non fra i riferimenti: sono
// materiale nostro, e in RIFERIMENTI/ ci vanno le mod altrui.
const DA = path.join(__dirname, '..', '..', 'art', 'sorgenti', 'icon');
const A = path.join(__dirname, '..', '..', 'workshop', 'Contents', 'mods',
    'ProjectWriting', '42.20', 'media', 'ui', 'NeatWriting');

const LATO = 128;

const ICONE = [
    ['worldmap.png', 'WorldMap.png'],
    ['createmapnote.png', 'CreateMapNote.png'],
    ['share.png', 'Share.png'],
    // Le due dell'ultimo giro, dalla stessa cartella e alla stessa misura.
    ['bin.png', 'Bin.png'],     // cancella i segni: prende il posto del punto
                                // interrogativo, che voleva dire tutt'altro
    ['moon.png', 'Moon.png'],   // la mappa in notturna, accanto al suo sole
];

function riduci(src, lato) {
    const out = Buffer.alloc(lato * lato * 4);
    const passo = src.w / lato;

    for (let y = 0; y < lato; y++) {
        const y0 = Math.floor(y * passo), y1 = Math.min(src.h, Math.ceil((y + 1) * passo));
        for (let x = 0; x < lato; x++) {
            const x0 = Math.floor(x * passo), x1 = Math.min(src.w, Math.ceil((x + 1) * passo));
            let r = 0, g = 0, b = 0, a = 0, n = 0;
            for (let j = y0; j < y1; j++) {
                for (let i = x0; i < x1; i++) {
                    const k = (j * src.w + i) * 4;
                    const al = src.rgba[k + 3] / 255;
                    r += src.rgba[k] * al;      // premoltiplicato: il colore dei
                    g += src.rgba[k + 1] * al;  // pixel trasparenti non conta
                    b += src.rgba[k + 2] * al;
                    a += src.rgba[k + 3];
                    n++;
                }
            }
            const k = (y * lato + x) * 4;
            const alpha = a / n;
            if (alpha > 0) {
                // e si torna indietro, dividendo per l'alfa medio
                const f = 255 / alpha;
                out[k]     = Math.min(255, Math.round(r / n * f));
                out[k + 1] = Math.min(255, Math.round(g / n * f));
                out[k + 2] = Math.min(255, Math.round(b / n * f));
            }
            out[k + 3] = Math.round(alpha);
        }
    }
    return out;
}

/** Vero se l'immagine non ha un canale alfa che dica qualcosa. */
function tuttaOpaca(rgba) {
    for (let i = 3; i < rgba.length; i += 4) {
        if (rgba[i] < 250) return false;
    }
    return true;
}

/** Da "disegno chiaro su fondo scuro, tutto opaco" a "bianco con l'alfa".
 *
 *  Le icone dei riferimenti sono immagini piene: fondo nero e figura chiara,
 *  nessuna trasparenza. Messe su un tasto sarebbero quadrati neri. Le nostre
 *  invece sono bianche e trasparenti, e il colore glielo da' il codice quando
 *  le disegna (drawTextureScaled con la tinta), che e' quello che permette a un
 *  tasto di accendersi restando la stessa icona.
 *
 *  La conversione e' quella classica: l'alfa diventa la luminanza, il colore
 *  bianco. La soglia toglie il grigio di fondo che altrimenti resterebbe come
 *  un velo quadrato attorno alla figura.
 */
function daLuminanza(rgba) {
    const SOGLIA = 18;
    for (let i = 0; i < rgba.length; i += 4) {
        const l = 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
        const a = l <= SOGLIA ? 0 : Math.min(255, Math.round((l - SOGLIA) * (255 / (255 - SOGLIA))));
        rgba[i] = 255; rgba[i + 1] = 255; rgba[i + 2] = 255;
        rgba[i + 3] = a;
    }
    return rgba;
}

let fatte = 0;
for (const [da, a] of ICONE) {
    const sorgente = path.join(DA, da);
    if (!fs.existsSync(sorgente)) {
        console.log('manca ' + da + ' nei riferimenti');
        continue;
    }
    const src = readPNG(sorgente);
    if (tuttaOpaca(src.rgba)) daLuminanza(src.rgba);
    writePNG(path.join(A, a), LATO, LATO, riduci(src, LATO));
    const peso = fs.statSync(path.join(A, a)).size;
    console.log(a + '  ' + src.w + 'x' + src.h + ' -> ' + LATO + 'x' + LATO
        + '  (' + peso + ' byte)');
    fatte++;
}
console.log(fatte + ' icone scritte in media/ui/NeatWriting/');
