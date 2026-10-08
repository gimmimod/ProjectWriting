/*  misure-scrittura.js - come cade la scrittura su ogni foglio.

    Rifa' fuori dal gioco il conto di NW_Writer.rhythm: si scrive sempre in
    Handwritten, che e' alta 40 pixel e non segue la scala dell'interfaccia,
    quindi il passo di scrittura e' l'altezza della grafia - salvo dove la carta
    ha righe stampate, e li' si aggancia al loro passo o a un suo multiplo.

    Serve a vedere in tabella, prima di aprire il gioco, se su ogni supporto
    resta un numero di righe sensato e battute per riga leggibili.

    Uso:  node MOD/ProjectWriting/strumenti/controlli/misure-scrittura.js [larghezza] [altezza]
*/
const fs = require('fs'), path = require('path');

const SW = Number(process.argv[2]) || 1920;
const SH = Number(process.argv[3]) || 1080;

// NW_Window.lua
const PANEL_W = 360, GAP = 16, MARGIN = 32, NAV_H = 26, NAV_GAP = 10;

// media/fonts/handwritten.fnt: size 40, lineHeight 40, base 30.
// Non sta nelle cartelle 1x/2x, quindi non cambia con la scala dell'interfaccia.
const HAND = 40;

// Avanzamento medio misurato su handwritten.fnt: 10.8 px su 40 di riga, cioe'
// 0.27 - le grafie sono strette, e stimarle a mezza riga sbagliava di quasi il
// doppio. MAX_CHARS e' il tetto di NW_Page:textRect.
const ADV = HAND * 0.27, MAX_CHARS = 90;


// --- legge il descrittore, invece di ricopiarlo -------------------------
const { leggi, controlla } = require('./descrittore');
const media = leggi();
controlla(media);

/** NW_Layouts.pageScale: la scala scende all'aggancio se costa poco. */
function pageScale(md, fit) {
    if (!md.ruled || !md.line) return { k: fit, snap: 0 };
    for (let i = 1; i <= 4; i++) {
        const s = HAND / (md.line * i);
        if (s <= fit) return s >= fit * 0.85 ? { k: s, snap: i } : { k: fit, snap: 0 };
    }
    return { k: fit, snap: 0 };
}

/** NW_Page:textRect, riga per riga.
 *
 *  Le righe le disegna il riquadro di vanilla e sono alte quanto la grafia: il
 *  passo non si sceglie. Dove la carta ha righe stampate il riquadro parte
 *  dalla prima, cosi' almeno l'attacco della scrittura cade dove deve.
 */
function rhythm(md, a, k, snap) {
    const y0 = (a[1] + md.marginY) * k;
    let top = y0;
    if (md.ruled) {
        top = md.first * k - HAND;
        if (top < y0) {
            // NW_Page:textRect: agganciati si scende di una riga intera, cosi'
            // si resta sulle righe stampate; non agganciati si schiaccia sul
            // margine, perche' non ci sarebbe niente da salvare.
            top = snap ? top + Math.ceil((y0 - top) / HAND) * HAND : y0;
        }
    }
    const h = (a[3] - md.marginY) * k - top;
    return { pitch: HAND, first: top, rows: Math.max(1, Math.floor(h / HAND)) };
}

console.log(`schermo ${SW}x${SH}  -  grafia Handwritten, ${HAND} px\n`);
console.log('supporto        pagina px    scala  riga px   righe  battute  pagine  righe stampate');
console.log('-'.repeat(88));

const warn = [];
for (const md of media) {
    const spreads = Math.max(1, Math.ceil(md.pages / md.areas.length));
    const navH = spreads > 1 ? NAV_H + NAV_GAP : 0;
    const fit = Math.min((SW - PANEL_W - GAP - MARGIN * 2) / md.w,
                         (SH - MARGIN * 2 - navH) / md.h);
    const ps = pageScale(md, fit);
    const k = ps.k;
    const pw = Math.floor(md.w * k), ph = Math.floor(md.h * k);

    const a = md.areas[0];
    const r = rhythm(md, a, k, ps.snap);
    // NW_Page:textRect stringe e centra la riga oltre il tetto di battute.
    const boxW = Math.min((a[2] - a[0] - md.margin * 2) * k, ADV * MAX_CHARS);
    const chars = Math.round(boxW / ADV);

    console.log(
        md.id.padEnd(15) +
        `${pw}x${ph}`.padEnd(13) +
        k.toFixed(3).padEnd(7) +
        r.pitch.toFixed(1).padEnd(10) +
        String(r.rows).padEnd(7) +
        String(chars).padEnd(9) +
        String(md.pages).padEnd(8) +
        (md.ruled
            ? `${(md.line * k).toFixed(1)}px ` + (ps.snap
                ? (ps.snap === 1 ? 'AGGANCIATO' : `AGGANCIATO 1 riga su ${ps.snap}`)
                : `sfasa ${(HAND - md.line * k).toFixed(1)}px per riga`)
            : '-'));

    if (r.rows < 8) warn.push(`${md.id}: solo ${r.rows} righe per facciata`);
    if (chars < 20) warn.push(`${md.id}: solo ${chars} battute per riga`);
    if (chars > 95) warn.push(`${md.id}: ${chars} battute per riga, la riga e' troppo lunga`);
    if (md.ruled && !ps.snap)
        warn.push(`${md.id}: righe stampate non agganciate, il testo sfasa ${(HAND - md.line * k).toFixed(1)}px per riga`);
    const boxH = (a[3] - a[1] - md.marginY * 2) * k;
    if (boxH < (a[3] - a[1]) * k * 0.6)
        warn.push(`${md.id}: il riquadro copre solo il ${Math.round(boxH / ((a[3] - a[1]) * k) * 100)}% dell'altezza della facciata`);
}

console.log();
if (warn.length === 0) console.log('nessun avviso.');
else warn.forEach(w => console.log('AVVISO  ' + w));
