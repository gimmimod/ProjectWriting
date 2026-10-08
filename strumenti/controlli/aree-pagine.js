/*  aree-pagine.js - dove si puo' scrivere su ogni supporto, misurato.

    Legge le immagini originali in Project Writing/canvas e ne ricava, per
    ognuna, i riquadri di carta scrivibile che finiscono in NW_Layouts.lua.
    Non si stima niente a occhio: si guardano i pixel.

    COME. Un pixel e' "carta" se e' opaco e chiaro. Le colonne che ne contengono
    abbastanza formano le facciate: una per il blocco, il foglio, la carta a
    quadretti e la scheda; due per quaderni e diari, separate dalla rilegatura.

    LA PIEGA. Fra le due facciate di un diario le colonne non si interrompono -
    la carta continua - ma si scuriscono, perche' li' il foglio si incurva. La
    si trova come avvallamento di luminosita' e si toglie una fascia simmetrica
    attorno al suo minimo: scrivere nella piega di un diario aperto non lo fa
    nessuno. Il quaderno non ne ha bisogno, la spirale interrompe gia' la carta.

    GLI ANELLI. Sul blocco la spirale sta in alto e non e' carta: le sue righe
    non passano la soglia e restano fuori dal riquadro da sole. Il controllo
    visivo qui sotto serve a vederlo.

    LE RIGHE. Sul quaderno a righe si cerca il passo delle righe stampate, che
    e' quello a cui deve andare la scrittura: da li' esce l'altezza di riga del
    descrittore, e in gioco si sceglie il font che ci si avvicina di piu'.

    Uso:  node MOD/ProjectWriting/strumenti/controlli/aree-pagine.js
          scrive art/verifica-aree.png e stampa il blocco Lua da incollare.
*/
const fs = require('fs'), zlib = require('zlib'), path = require('path');

// --- PNG ---------------------------------------------------------------
let T = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; T[n] = c; }
const crc = b => { let c = 0xFFFFFFFF; for (const x of b) c = T[(c ^ x) & 0xFF] ^ (c >>> 8); return c ^ 0xFFFFFFFF; };

function readPNG(file) {
    const b = fs.readFileSync(file); let p = 8, idat = [], w, h, ct, pal = null, trns = null;
    while (p < b.length) {
        const len = b.readUInt32BE(p), t = b.toString('latin1', p + 4, p + 8);
        if (t === 'IHDR') { w = b.readUInt32BE(p + 8); h = b.readUInt32BE(p + 12); ct = b[p + 17]; }
        else if (t === 'PLTE') pal = b.slice(p + 8, p + 8 + len);
        else if (t === 'tRNS') trns = b.slice(p + 8, p + 8 + len);
        else if (t === 'IDAT') idat.push(b.slice(p + 8, p + 8 + len));
        p += 12 + len;
    }
    const raw = zlib.inflateSync(Buffer.concat(idat));
    const ch = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[ct], stride = w * ch;
    const out = Buffer.alloc(h * stride); let pos = 0;
    for (let y = 0; y < h; y++) {
        const ft = raw[pos++]; const line = raw.slice(pos, pos + stride); pos += stride;
        for (let i = 0; i < stride; i++) {
            const a = i >= ch ? out[y * stride + i - ch] : 0, bb = y > 0 ? out[(y - 1) * stride + i] : 0,
                c = (i >= ch && y > 0) ? out[(y - 1) * stride + i - ch] : 0;
            let v = line[i];
            if (ft === 1) v += a; else if (ft === 2) v += bb; else if (ft === 3) v += Math.floor((a + bb) / 2);
            else if (ft === 4) { const pp = a + bb - c, pa = Math.abs(pp - a), pb = Math.abs(pp - bb), pc = Math.abs(pp - c); v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? bb : c); }
            out[y * stride + i] = v & 255;
        }
    }
    const rgba = Buffer.alloc(w * h * 4);
    for (let i = 0; i < w * h; i++) {
        let r, g, b2, a = 255;
        if (ct === 0) { r = g = b2 = out[i]; }
        else if (ct === 2) { r = out[i * 3]; g = out[i * 3 + 1]; b2 = out[i * 3 + 2]; }
        else if (ct === 3) { const ix = out[i]; r = pal[ix * 3]; g = pal[ix * 3 + 1]; b2 = pal[ix * 3 + 2]; if (trns && ix < trns.length) a = trns[ix]; }
        else if (ct === 4) { r = g = b2 = out[i * 2]; a = out[i * 2 + 1]; }
        else { r = out[i * 4]; g = out[i * 4 + 1]; b2 = out[i * 4 + 2]; a = out[i * 4 + 3]; }
        rgba[i * 4] = r; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = b2; rgba[i * 4 + 3] = a;
    }
    return { w, h, rgba };
}

function writePNG(file, w, h, px) {
    const stride = w * 4 + 1, raw = Buffer.alloc(h * stride);
    for (let y = 0; y < h; y++) { raw[y * stride] = 0; px.copy(raw, y * stride + 1, y * w * 4, (y + 1) * w * 4); }
    const chunk = (t, d) => {
        const l = Buffer.alloc(4); l.writeUInt32BE(d.length);
        const td = Buffer.concat([Buffer.from(t, 'latin1'), d]);
        const c = Buffer.alloc(4); c.writeUInt32BE(crc(td) >>> 0);
        return Buffer.concat([l, td, c]);
    };
    const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 6;
    fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
        chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]));
}

// --- i supporti ---------------------------------------------------------
// Le immagini di partenza stanno nella mod, non piu' in una cartella accanto:
// uno strumento che legge da fuori dal progetto smette di funzionare il giorno
// che qualcuno riordina la scrivania, e infatti era successo.
const SRC = path.join(__dirname, 'sorgenti', 'canvas');
const MEDIA = [
    { id: 'sheet',          file: 'Note.png',             sheets: 1 },
    { id: 'notepad',        file: 'notepad.png',          sheets: 1 },
    { id: 'notebook',       file: 'notebook.png',         sheets: 2 },
    { id: 'notebook_lines', file: 'notebook (lines).png', sheets: 2, ruled: true },
    { id: 'diary_blue',     file: 'Diary (Blue).png',     sheets: 2, fold: true },
    { id: 'diary_red',      file: 'Diary (red).png',      sheets: 2, fold: true },
    { id: 'graph_paper',    file: 'square.png',           sheets: 1, ruled: true },
    { id: 'index_card',     file: 'lines.png',            sheets: 1, ruled: true },
    { id: 'card',           file: 'card.png',             sheets: 1 },
];

// La fascia tolta attorno alla piega, in frazione di larghezza. Il quaderno la
// ha gia' per conto suo (la spirale interrompe la carta) ed e' larga il 6%:
// questo numero viene da li', non da un gusto.
const FOLD_HALF = 0.031;

function paperMask(im) {
    const { w: W, h: H, rgba: d } = im;
    const m = new Uint8Array(W * H);
    for (let i = 0; i < W * H; i++) {
        if (d[i * 4 + 3] < 200) continue;
        if (0.299 * d[i * 4] + 0.587 * d[i * 4 + 1] + 0.114 * d[i * 4 + 2] > 140) m[i] = 1;
    }
    return m;
}

/** L'altezza vera di una facciata, misurata sulle sue colonne e non su quelle
    del foglio intero: la piega di un diario scende piu' in basso della carta. */
function vertical(im, m, x0, x1) {
    const { w: W, h: H } = im;
    const cnt = new Int32Array(H);
    for (let y = 0; y < H; y++) { let c = 0; for (let x = x0; x <= x1; x++) if (m[y * W + x]) c++; cnt[y] = c; }
    const t = Math.max(...cnt) * 0.6;
    let y0 = -1, y1 = -1;
    for (let y = 0; y < H; y++) if (cnt[y] >= t) { if (y0 < 0) y0 = y; y1 = y; }
    return [y0, y1];
}

function areasOf(im, spec) {
    const { w: W, h: H } = im, m = paperMask(im);
    const colCount = new Int32Array(W);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (m[y * W + x]) colCount[x]++;
    const thr = Math.max(...colCount) * 0.55;

    const runs = []; let s = -1;
    for (let x = 0; x < W; x++) {
        if (colCount[x] >= thr) { if (s < 0) s = x; }
        else { if (s >= 0 && x - s > W * 0.05) runs.push([s, x - 1]); s = -1; }
    }
    if (s >= 0 && W - s > W * 0.05) runs.push([s, W - 1]);

    const boxes = runs.map(([x0, x1]) => {
        const cnt = new Int32Array(H);
        for (let y = 0; y < H; y++) { let c = 0; for (let x = x0; x <= x1; x++) if (m[y * W + x]) c++; cnt[y] = c; }
        const t = Math.max(...cnt) * 0.6;
        let y0 = -1, y1 = -1;
        for (let y = 0; y < H; y++) if (cnt[y] >= t) { if (y0 < 0) y0 = y; y1 = y; }
        return [x0, y0, x1, y1];
    });

    // La piega: un'unica corsa di colonne dove ce ne vorrebbero due.
    let fold = null;
    if (spec.sheets === 2 && boxes.length < 2) {
        const y0 = Math.floor(H * 0.3), y1 = Math.floor(H * 0.7);
        const col = new Float64Array(W);
        for (let x = 0; x < W; x++) {
            let sum = 0, n = 0;
            for (let y = y0; y < y1; y++) {
                const o = (y * W + x) * 4;
                if (im.rgba[o + 3] < 200) continue;
                sum += 0.299 * im.rgba[o] + 0.587 * im.rgba[o + 1] + 0.114 * im.rgba[o + 2]; n++;
            }
            col[x] = n ? sum / n : 1e9;
        }
        let best = Math.floor(W / 2), bestV = 1e9;
        for (let x = Math.floor(W * 0.42); x < Math.floor(W * 0.58); x++)
            if (col[x] < bestV) { bestV = col[x]; best = x; }
        fold = best;
    }
    // Due facciate ma una corsa sola: si taglia la corsa in due sulla piega.
    if (spec.sheets === 2 && boxes.length === 1 && fold !== null) {
        const [x0, y0, x1, y1] = boxes[0];
        const half = Math.round(W * FOLD_HALF);
        return { boxes: [[x0, y0, fold - half, y1], [fold + half, y0, x1, y1]], fold, cut: half * 2 };
    }
    // Due corse gia' separate, ma da una fessura troppo stretta per essere una
    // rilegatura: si allarga fino alla stessa misura.
    if (spec.sheets === 2 && boxes.length === 2) {
        const gap = boxes[1][0] - boxes[0][2];
        const centre = Math.round((boxes[0][2] + boxes[1][0]) / 2);
        const want = Math.round(W * FOLD_HALF * 2);
        if (gap < want) {
            const half = Math.round(want / 2);
            boxes[0][2] = centre - half;
            boxes[1][0] = centre + half;
            return { boxes, fold: centre, cut: want };
        }
        return { boxes, fold: centre, cut: gap };
    }
    return { boxes, fold: null, cut: 0 };
}

/** Rimisura l'altezza di ogni facciata sulle proprie colonne. */
function tighten(im, res) {
    const m = paperMask(im);
    for (const b of res.boxes) {
        const [y0, y1] = vertical(im, m, b[0], b[2]);
        if (y0 >= 0) { b[1] = y0; b[3] = y1; }
    }
    return res;
}

/** Il passo delle righe stampate, dentro la prima facciata. */
function ruleStep(im, box) {
    const { w: W, rgba: d } = im;
    const [x0, y0, x1, y1] = box;
    const row = [];
    for (let y = y0; y <= y1; y++) {
        let s = 0, n = 0;
        for (let x = x0 + 20; x <= x1 - 20; x++) {
            const o = (y * W + x) * 4;
            s += 0.299 * d[o] + 0.587 * d[o + 1] + 0.114 * d[o + 2]; n++;
        }
        row.push(s / n);
    }
    const med = [...row].sort((a, b) => a - b)[Math.floor(row.length / 2)];
    const hits = [];
    for (let i = 1; i < row.length - 1; i++)
        if (row[i] < med - 3 && row[i] <= row[i - 1] && row[i] < row[i + 1]) hits.push(y0 + i);
    // Due minimi a tre pixel di distanza sono lo stesso tratto visto due volte,
    // oppure il bordo del foglio: il passo di una riga non scende sotto i venti.
    const keep = [];
    for (const h of hits) if (keep.length === 0 || h - keep[keep.length - 1] >= 20) keep.push(h);
    if (keep.length < 5) return null;
    // La prima riga VERA e quella da cui parte una serie regolare: sopra ci sono
    // spesso una riga di intestazione e il bordo, che non sono righe da scrivere.
    const gaps = [];
    for (let i = 1; i < keep.length; i++) gaps.push(keep[i] - keep[i - 1]);
    const sorted = [...gaps].sort((a, b) => a - b);
    const med2 = sorted[Math.floor(sorted.length / 2)];
    let start = 0;
    for (let i = 0; i < keep.length - 2; i++)
        if (Math.abs(keep[i + 1] - keep[i] - med2) <= 2 && Math.abs(keep[i + 2] - keep[i + 1] - med2) <= 2) { start = i; break; }
    // I passi fuori misura si buttano, la serie no. L'ultimo minimo di un foglio
    // e' quasi sempre il suo bordo, e su una fotografia di carta vera un paio di
    // righe capitano storte: interrompere la serie al primo scarto faceva
    // misurare undici righe su ventitre' e sbagliare il passo di due pixel.
    // Il passo si misura fra la prima riga e l'ultima, non come media dei salti:
    // su una fotografia di carta vera le righe ballano di un paio di pixel
    // ciascuna, e mediare gli scarti li somma invece di annullarli.
    //
    // Prima pero' si buttano le code: l'ultimo minimo di un foglio e' quasi
    // sempre il suo bordo, e sta molto piu' lontano di una riga.
    const run = keep.slice(start);
    while (run.length > 4 && run[run.length - 1] - run[run.length - 2] > med2 * 1.4) run.pop();
    if (run.length < 5) return null;
    const step = (run[run.length - 1] - run[0]) / (run.length - 1);
    return { step: Math.round(step * 100) / 100, first: run[0], count: run.length };
}

// --- misura, e disegna il controllo -------------------------------------
const TILE = 460, COLS = 4, PADT = 10;
const ROWS = Math.ceil(MEDIA.length / COLS);
const CW = COLS * TILE, CH = ROWS * (TILE + 22);
const sheet = Buffer.alloc(CW * CH * 4);
for (let i = 0; i < CW * CH; i++) { sheet[i * 4] = 18; sheet[i * 4 + 1] = 18; sheet[i * 4 + 2] = 20; sheet[i * 4 + 3] = 255; }

const lua = [];
MEDIA.forEach((spec, n) => {
    const im = readPNG(path.join(SRC, spec.file));
    const r = tighten(im, areasOf(im, spec));
    let ruled = null;
    if (spec.ruled) ruled = ruleStep(im, r.boxes[0]);

    const areas = r.boxes.map(b => `{ ${b[0]}, ${b[1]}, ${b[2]}, ${b[3]} }`).join(', ');
    lua.push(`  ${spec.id.padEnd(15)} ${im.w}x${im.h}  areas = { ${areas} }`
        + (r.fold !== null ? `   piega ${r.fold}, tolti ${r.cut} px` : '')
        + (ruled ? `   righe: passo ${ruled.step}, prima ${ruled.first}, trovate ${ruled.count}` : ''));

    // riquadro nel foglio di controllo
    const col = n % COLS, row = Math.floor(n / COLS);
    const ox = col * TILE, oy = row * (TILE + 22);
    const k = Math.min((TILE - PADT * 2) / im.w, (TILE - PADT * 2) / im.h);
    const dw = Math.round(im.w * k), dh = Math.round(im.h * k);
    const dx = ox + Math.floor((TILE - dw) / 2), dy = oy + Math.floor((TILE - dh) / 2);
    for (let j = 0; j < dh; j++) for (let i = 0; i < dw; i++) {
        const u = Math.min(im.w - 1, Math.floor(i / k)), v = Math.min(im.h - 1, Math.floor(j / k));
        const o = (v * im.w + u) * 4, a = im.rgba[o + 3] / 255;
        const p = ((dy + j) * CW + dx + i) * 4;
        sheet[p] = im.rgba[o] * a + sheet[p] * (1 - a);
        sheet[p + 1] = im.rgba[o + 1] * a + sheet[p + 1] * (1 - a);
        sheet[p + 2] = im.rgba[o + 2] * a + sheet[p + 2] * (1 - a);
    }
    const mark = (x, y, cr, cg, cb) => {
        if (x < 0 || y < 0 || x >= CW || y >= CH) return;
        const p = (y * CW + x) * 4; sheet[p] = cr; sheet[p + 1] = cg; sheet[p + 2] = cb;
    };
    for (const b of r.boxes) {
        const X0 = dx + Math.round(b[0] * k), Y0 = dy + Math.round(b[1] * k);
        const X1 = dx + Math.round(b[2] * k), Y1 = dy + Math.round(b[3] * k);
        for (let x = X0; x <= X1; x++) { mark(x, Y0, 230, 120, 40); mark(x, Y1, 230, 120, 40); }
        for (let y = Y0; y <= Y1; y++) { mark(X0, y, 230, 120, 40); mark(X1, y, 230, 120, 40); }
    }
    if (ruled) for (let i = 0; i < 40; i++) {
        const y = dy + Math.round((ruled.first + i * ruled.step) * k);
        if (y > dy + dh) break;
        for (let x = dx + Math.round(r.boxes[0][0] * k); x < dx + Math.round(r.boxes[0][2] * k); x += 3)
            mark(x, y, 60, 200, 120);
    }
});

writePNG(path.join(__dirname, '..', '..', 'art', 'anteprime', 'verifica-aree.png'), CW, CH, sheet);
console.log(lua.join('\n'));
console.log('\nscritto art/verifica-aree.png');
