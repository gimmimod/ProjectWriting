/*  genera-icone-matita.js - le quattro icone del giro di correzioni della 1.2.2.
 *
 *      pencil-write.png  -> PencilWrite.png   la punta: la matita scrive
 *      pencil-erase.png  -> PencilErase.png   il fondo con la gommetta: cancella
 *      helicopter.png    -> Follow.png        la mappa segue il personaggio
 *      magazine.png      -> Magazine.png      la lettura: pannello e tasto della mappa
 *      info.png          -> Info.png          la trascrizione di una stampa
 *      zoom-in.png       -> ZoomIn.png        il + della mappa
 *      zoom-out.png      -> ZoomOut.png       il - della mappa
 *      view-top.png      -> ViewTop.png       vista dall'alto (mappa e segni)
 *      view-isometric.png-> ViewIsometric.png vista isometrica (mappa e segni)
 *
 *  Tutte in art/sorgenti/icon/ e tutte a 128x128 bianco su trasparente, come
 *  Pen.png e le altre. Arrivano in tre forme diverse, ed e' per questo che
 *  questo script non e' genera-icone-share.js con una riga in piu':
 *
 *    - le due matite sono 1080x1080 RGBA: basta rimpicciolirle;
 *    - l'elicottero e' 1254x1254 SENZA canale alfa, bianco su nero: l'alfa si
 *      ricava dalla luminosita', altrimenti in gioco resterebbe un quadrato nero
 *      tinto dal colore del tasto;
 *    - la rivista e' 64x64: va INGRANDITA, e il rimpicciolimento a media di
 *      scatola non sa andare in su (lo stesso per info, + e -);
 *    - le due viste sono 1254x1254 bianco su nero come l'elicottero, ma col
 *      disegno che occupa meta' del foglio - la vista dall'alto meno di
 *      quella isometrica. Si RITAGLIANO sul disegno e si rimettono al centro
 *      a una frazione fissa del lato: stanno sullo stesso tasto a turno, e
 *      una che salta di misura a ogni clic sembra un'altra icona.
 *
 *  Come in genera-icone-share.js, ogni media si fa in alfa premoltiplicato:
 *  senza, i pixel trasparenti tirano il bordo verso il nero e resta un alone.
 *
 *      node MOD/ProjectWriting/strumenti/arte/genera-icone-matita.js
 */
const path = require('path');
const { readPNG, writePNG } = require('../controlli/png.js');

const DA = path.join(__dirname, '..', '..', 'art', 'sorgenti', 'icon');
const A = path.join(__dirname, '..', '..', 'workshop', 'Contents', 'mods',
    'ProjectWriting', '42.20', 'media', 'ui', 'NeatWriting');

const LATO = 128;

/** Legge un PNG e lo porta sempre a RGBA a 8 bit per canale. */
function leggi(file) {
    const im = readPNG(file);
    const n = im.w * im.h;
    const ch = im.rgba.length / n;
    if (ch === 4) return im;
    const out = Buffer.alloc(n * 4);
    for (let i = 0; i < n; i++) {
        if (ch === 3) {
            out[i * 4] = im.rgba[i * 3]; out[i * 4 + 1] = im.rgba[i * 3 + 1];
            out[i * 4 + 2] = im.rgba[i * 3 + 2];
        } else {
            out[i * 4] = out[i * 4 + 1] = out[i * 4 + 2] = im.rgba[i * ch];
        }
        out[i * 4 + 3] = 255;
    }
    return { w: im.w, h: im.h, rgba: out };
}

/** Bianco su nero -> bianco su trasparente: l'alfa e' la luminosita'. */
function alfaDaLuce(im) {
    const out = Buffer.alloc(im.rgba.length);
    for (let i = 0; i < im.w * im.h; i++) {
        const k = i * 4;
        const lum = 0.30 * im.rgba[k] + 0.59 * im.rgba[k + 1] + 0.11 * im.rgba[k + 2];
        out[k] = out[k + 1] = out[k + 2] = 255;
        out[k + 3] = Math.round(lum);
    }
    return { w: im.w, h: im.h, rgba: out };
}

/** Ritaglia sul disegno (alfa > 8) e lo centra in un quadrato di cui occupa
 *  `frazione` del lato, sul lato piu' lungo. */
function centra(im, frazione) {
    let x0 = im.w, y0 = im.h, x1 = -1, y1 = -1;
    for (let y = 0; y < im.h; y++) for (let x = 0; x < im.w; x++) {
        if (im.rgba[(y * im.w + x) * 4 + 3] > 8) {
            x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y);
        }
    }
    const gw = x1 - x0 + 1, gh = y1 - y0 + 1;
    const lato = Math.ceil(Math.max(gw, gh) / frazione);
    const out = Buffer.alloc(lato * lato * 4);
    const ox = Math.floor((lato - gw) / 2), oy = Math.floor((lato - gh) / 2);
    for (let y = 0; y < gh; y++) im.rgba.copy(out, ((oy + y) * lato + ox) * 4, ((y0 + y) * im.w + x0) * 4, ((y0 + y) * im.w + x1 + 1) * 4);
    return { w: lato, h: lato, rgba: out };
}

/** Rimpicciolisce a media di scatola, in alfa premoltiplicato. */
function riduci(src, lato) {
    const out = Buffer.alloc(lato * lato * 4);
    const px = src.w / lato, py = src.h / lato;
    for (let y = 0; y < lato; y++) {
        const y0 = Math.floor(y * py), y1 = Math.min(src.h, Math.ceil((y + 1) * py));
        for (let x = 0; x < lato; x++) {
            const x0 = Math.floor(x * px), x1 = Math.min(src.w, Math.ceil((x + 1) * px));
            let r = 0, g = 0, b = 0, a = 0, n = 0;
            for (let j = y0; j < y1; j++) {
                for (let i = x0; i < x1; i++) {
                    const k = (j * src.w + i) * 4;
                    const al = src.rgba[k + 3] / 255;
                    r += src.rgba[k] * al; g += src.rgba[k + 1] * al; b += src.rgba[k + 2] * al;
                    a += src.rgba[k + 3]; n++;
                }
            }
            scrivi(out, (y * lato + x) * 4, r / n, g / n, b / n, a / n);
        }
    }
    return out;
}

/** Ingrandisce in bilineare, in alfa premoltiplicato. */
function ingrandisci(src, lato) {
    const out = Buffer.alloc(lato * lato * 4);
    const at = (i, j, c) => src.rgba[(Math.min(src.h - 1, j) * src.w + Math.min(src.w - 1, i)) * 4 + c];
    for (let y = 0; y < lato; y++) {
        const fy = (y + 0.5) * src.h / lato - 0.5, j = Math.max(0, Math.floor(fy)), ty = Math.max(0, fy - j);
        for (let x = 0; x < lato; x++) {
            const fx = (x + 0.5) * src.w / lato - 0.5, i = Math.max(0, Math.floor(fx)), tx = Math.max(0, fx - i);
            let r = 0, g = 0, b = 0, a = 0;
            for (const [ii, jj, w] of [[i, j, (1 - tx) * (1 - ty)], [i + 1, j, tx * (1 - ty)],
                                       [i, j + 1, (1 - tx) * ty], [i + 1, j + 1, tx * ty]]) {
                const al = at(ii, jj, 3) / 255;
                r += at(ii, jj, 0) * al * w; g += at(ii, jj, 1) * al * w; b += at(ii, jj, 2) * al * w;
                a += at(ii, jj, 3) * w;
            }
            scrivi(out, (y * lato + x) * 4, r, g, b, a);
        }
    }
    return out;
}

/** Da premoltiplicato a normale, dividendo per l'alfa medio. */
function scrivi(out, k, r, g, b, a) {
    if (a > 0) {
        const f = 255 / a;
        out[k] = Math.min(255, Math.round(r * f));
        out[k + 1] = Math.min(255, Math.round(g * f));
        out[k + 2] = Math.min(255, Math.round(b * f));
    }
    out[k + 3] = Math.round(a);
}

const ICONE = [
    ['pencil-write.png', 'PencilWrite.png', 'rgba'],
    ['pencil-erase.png', 'PencilErase.png', 'rgba'],
    ['helicopter.png',   'Follow.png',      'luce'],
    ['magazine.png',     'Magazine.png',    'rgba'],
    ['info.png',         'Info.png',        'rgba'],
    ['zoom-in.png',      'ZoomIn.png',      'rgba'],
    ['zoom-out.png',     'ZoomOut.png',     'rgba'],
    // Le due viste: la frazione e' sul lato lungo. L'isometrica e' larga e
    // bassa, la vista dall'alto e' un quadrato pieno e a parita' di lato pesa
    // di piu': un filo piu' piccola, cosi' le due si scambiano senza saltare.
    ['view-isometric.png', 'ViewIsometric.png', 'luce', 0.86],
    ['view-top.png',     'ViewTop.png',     'luce', 0.72],
];

for (const [da, a, forma, frazione] of ICONE) {
    let im = leggi(path.join(DA, da));
    if (forma === 'luce') im = alfaDaLuce(im);
    if (frazione) im = centra(im, frazione);
    const px = im.w >= LATO ? riduci(im, LATO) : ingrandisci(im, LATO);
    writePNG(path.join(A, a), LATO, LATO, px);
    console.log(`  ${da.padEnd(18)} ${String(im.w).padStart(4)}x${im.h} -> ${a} ${LATO}x${LATO}`);
}
