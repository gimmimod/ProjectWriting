/*  estrai-icona.js - tira fuori un'icona del gioco dai suoi texture pack.

    Le icone d'inventario non sono file: stanno dentro i .pack di
    media/texturepacks, atlanti con un indice davanti. Il formato e' semplice e
    ne esistono due versioni, che qui si leggono tutte e due:

        [PZPK + versione]          solo nel formato nuovo
        int32 numero di pagine
        per ogni pagina:
            stringa nome, int32 numero di voci, int32 flag
            per ogni voce: nome, x, y, w, h, offsetX, offsetY, origW, origH
            il PNG della pagina - nel formato nuovo preceduto dalla sua
            lunghezza, nel vecchio attaccato di seguito fino a IEND

    Le voci sono RITAGLIATE: `w x h` e' il pezzo che sta nell'atlante e
    `offset` dice dove rimetterlo dentro il riquadro originale. Ricomporlo
    conta, perche' un'icona centrata a mano ha il suo margine e senza quello
    tutte le icone finiscono disallineate fra loro.

    ALTA RISOLUZIONE. Le icone del gioco sono PIXEL ART: 32x32, alfa binaria,
    una dozzina di colori, zero antialiasing. Su roba cosi' un ingrandimento
    morbido - bicubico, campo di distanza, quello che si usa per i caratteri -
    fa il danno peggiore: sfoca l'interno e lascia lo stesso il bordo a scaletta,
    perche' la scaletta e' nel disegno, non nel campionamento.

    Si usa allora Scale2x (EPX), che e' fatto per questo: guarda i quattro
    vicini di ogni pixel e arrotonda le diagonali **senza inventare colori**.
    Applicato quattro volte porta da 32 a 512, e la tavolozza resta quella di
    partenza.

    La scelta e' automatica e si vede dalla sorgente: alfa a due soli valori e
    pochi colori vuol dire pixel art, e allora EPX; altrimenti l'immagine ha gia'
    le sue sfumature e si ingrandisce in bicubica su alfa premoltiplicato -
    senza premoltiplicare, ai bordi si tira dentro il colore dei pixel
    trasparenti e resta un alone.

    Uso:  node MOD/ProjectWriting/strumenti/arte/estrai-icona.js Item_Pen Item_Pencil [lato]
          senza nomi, elenca tutto quello che somiglia a "Pen".
*/
const fs = require('fs'), zlib = require('zlib'), path = require('path');

const PACKS = 'C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/media/texturepacks';
const args = process.argv.slice(2);
const SIDE = Number(args[args.length - 1]) > 0 ? Number(args.pop()) : 512;
const NAMES = args;
const OUT = path.join(__dirname, '..', '..', '..', '..', 'Project Writing', 'icone');

// --- PNG ---------------------------------------------------------------
let T = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; T[n] = c; }
const crc = b => { let c = 0xFFFFFFFF; for (const x of b) c = T[(c ^ x) & 0xFF] ^ (c >>> 8); return c ^ 0xFFFFFFFF; };

function decodePNG(buf) {
    let p = 8, idat = [], w, h, depth, ct, pal = null, trns = null;
    while (p < buf.length) {
        const len = buf.readUInt32BE(p), t = buf.toString('latin1', p + 4, p + 8);
        const d = buf.slice(p + 8, p + 8 + len);
        if (t === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); depth = d[8]; ct = d[9]; }
        else if (t === 'PLTE') pal = d;
        else if (t === 'tRNS') trns = d;
        else if (t === 'IDAT') idat.push(d);
        else if (t === 'IEND') break;
        p += 12 + len;
    }
    if (depth !== 8) throw new Error('profondita ' + depth + ' non gestita');
    const chan = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[ct], stride = w * chan;
    const raw = zlib.inflateSync(Buffer.concat(idat));
    const out = Buffer.alloc(h * stride);
    let q = 0;
    for (let y = 0; y < h; y++) {
        const f = raw[q++], line = raw.slice(q, q + stride); q += stride;
        for (let i = 0; i < stride; i++) {
            const a = i >= chan ? out[y * stride + i - chan] : 0;
            const bb = y > 0 ? out[(y - 1) * stride + i] : 0;
            const c = (i >= chan && y > 0) ? out[(y - 1) * stride + i - chan] : 0;
            let v = line[i];
            if (f === 1) v += a; else if (f === 2) v += bb; else if (f === 3) v += (a + bb) >> 1;
            else if (f === 4) { const pp = a + bb - c, pa = Math.abs(pp - a), pb = Math.abs(pp - bb), pc = Math.abs(pp - c); v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? bb : c); }
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

// --- il pacchetto -------------------------------------------------------
const PNGSIG   = Buffer.from([0x89, 0x50, 0x4e, 0x47]);
// Nel formato vecchio ogni pagina si chiude con questo, fra un PNG e il nome
// della pagina successiva.
const DEADBEEF = Buffer.from([0xef, 0xbe, 0xad, 0xde]);

function readPack(file) {
    const b = fs.readFileSync(file);
    let p = 0;
    const i32 = () => { const v = b.readInt32LE(p); p += 4; return v; };
    const str = () => { const n = i32(); const s = b.toString('latin1', p, p + n); p += n; return s; };

    if (b.toString('latin1', 0, 4) === 'PZPK') { p = 4; i32(); }
    const pages = [];
    const n = i32();
    for (let pg = 0; pg < n; pg++) {
        const name = str(), count = i32();
        i32();                                   // flag: 1 dove l'immagine e' preceduta dalla lunghezza
        const entries = [];
        for (let e = 0; e < count; e++) {
            entries.push({
                name: str(), x: i32(), y: i32(), w: i32(), h: i32(),
                ox: i32(), oy: i32(), ow: i32(), oh: i32(),
            });
        }
        // Il formato nuovo mette la lunghezza davanti al PNG; il vecchio lo
        // attacca di seguito e chiude la pagina con un DEADBEEF.
        let start;
        if (b.slice(p, p + 4).equals(PNGSIG)) {
            start = p;
            p += 8;                              // oltre la firma
            while (p < b.length) {               // si percorrono i chunk fino a IEND
                const len = b.readUInt32BE(p);
                const type = b.toString('latin1', p + 4, p + 8);
                p += 12 + len;
                if (type === 'IEND') break;
            }
        } else {
            const len = i32(); start = p; p += len;
        }
        const png = b.slice(start, p);
        if (b.slice(p, p + 4).equals(DEADBEEF)) p += 4;
        pages.push({ name, entries, png: png });
    }
    return pages;
}

// --- ingrandimento -------------------------------------------------------
function cubic(a, b, c, d, t) {
    return b + 0.5 * t * (c - a + t * (2 * a - 5 * b + 4 * c - d + t * (3 * (b - c) + d - a)));
}

/** Campo di distanza con segno dalla maschera di opacita'. */
function sdf(alpha, w, h) {
    const INF = 1e20;
    const f = new Float64Array(Math.max(w, h)), d = new Float64Array(Math.max(w, h));
    const v = new Int32Array(Math.max(w, h) + 1), z = new Float64Array(Math.max(w, h) + 1);
    function edt1d(n) {
        let k = 0; v[0] = 0; z[0] = -INF; z[1] = INF;
        for (let q = 1; q < n; q++) {
            let s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
            while (s <= z[k]) { k--; s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]); }
            k++; v[k] = q; z[k] = s; z[k + 1] = INF;
        }
        k = 0;
        for (let q = 0; q < n; q++) { while (z[k + 1] < q) k++; d[q] = (q - v[k]) * (q - v[k]) + f[v[k]]; }
    }
    function edt(seed) {
        const out = new Float64Array(w * h);
        for (let y = 0; y < h; y++) {
            for (let x = 0; x < w; x++) f[x] = seed[y * w + x] ? 0 : INF;
            edt1d(w);
            for (let x = 0; x < w; x++) out[y * w + x] = d[x];
        }
        for (let x = 0; x < w; x++) {
            for (let y = 0; y < h; y++) f[y] = out[y * w + x];
            edt1d(h);
            for (let y = 0; y < h; y++) out[y * w + x] = Math.sqrt(d[y]);
        }
        return out;
    }
    const inS = new Uint8Array(w * h), outS = new Uint8Array(w * h);
    for (let i = 0; i < w * h; i++) { if (alpha[i] >= 0.5) inS[i] = 1; else outS[i] = 1; }
    const dIn = edt(outS), dOut = edt(inS);
    const dist = new Float64Array(w * h);
    for (let i = 0; i < w * h; i++) {
        const a = alpha[i];
        if (a > 0.02 && a < 0.98) dist[i] = a - 0.5;
        else if (a >= 0.5) dist[i] = dIn[i] - 0.5;
        else dist[i] = -(dOut[i] - 0.5);
    }
    return dist;
}

/** Ingrandisce un'icona: colore in bicubica, sagoma dal campo di distanza. */
function upscale(src, w, h, scale) {
    // premoltiplicato: senza, ai bordi si tira dentro il colore dei pixel
    // trasparenti e resta un alone scuro attorno alla sagoma
    const pr = new Float64Array(w * h), pg = new Float64Array(w * h), pb = new Float64Array(w * h);
    const al = new Float64Array(w * h);
    for (let i = 0; i < w * h; i++) {
        const a = src[i * 4 + 3] / 255;
        al[i] = a;
        pr[i] = src[i * 4] / 255 * a; pg[i] = src[i * 4 + 1] / 255 * a; pb[i] = src[i * 4 + 2] / 255 * a;
    }
    const dist = sdf(al, w, h);

    const at = (m, x, y) => m[Math.max(0, Math.min(h - 1, y)) * w + Math.max(0, Math.min(w - 1, x))];
    const bicubic = (m, sx, sy) => {
        const ix = Math.floor(sx), iy = Math.floor(sy), fx = sx - ix, fy = sy - iy;
        const col = [];
        for (let j = -1; j <= 2; j++) {
            col.push(cubic(at(m, ix - 1, iy + j), at(m, ix, iy + j), at(m, ix + 1, iy + j), at(m, ix + 2, iy + j), fx));
        }
        return cubic(col[0], col[1], col[2], col[3], fy);
    };
    const bilinear = (m, sx, sy) => {
        const x = Math.max(0, Math.min(w - 1.001, sx)), y = Math.max(0, Math.min(h - 1.001, sy));
        const ix = Math.floor(x), iy = Math.floor(y), tx = x - ix, ty = y - iy;
        const jx = Math.min(w - 1, ix + 1), jy = Math.min(h - 1, iy + 1);
        return (m[iy * w + ix] * (1 - tx) + m[iy * w + jx] * tx) * (1 - ty)
             + (m[jy * w + ix] * (1 - tx) + m[jy * w + jx] * tx) * ty;
    };

    const OW = Math.round(w * scale), OH = Math.round(h * scale);
    const out = Buffer.alloc(OW * OH * 4);
    const soft = 1.0 / scale;
    for (let oy = 0; oy < OH; oy++) {
        const sy = (oy + 0.5) / scale - 0.5;
        for (let ox = 0; ox < OW; ox++) {
            const sx = (ox + 0.5) / scale - 0.5;
            let a = 0.5 + bilinear(dist, sx, sy) / soft;
            a = a < 0 ? 0 : a > 1 ? 1 : a;
            const o = (oy * OW + ox) * 4;
            if (a <= 0) { out[o + 3] = 0; continue; }
            // si torna al colore non premoltiplicato dividendo per l'alfa
            // dell'originale, non per quello ricostruito
            const aa = Math.max(0.02, bicubic(al, sx, sy));
            const r = bicubic(pr, sx, sy) / aa, g = bicubic(pg, sx, sy) / aa, b = bicubic(pb, sx, sy) / aa;
            const clamp = v => Math.round(Math.max(0, Math.min(1, v)) * 255);
            out[o] = clamp(r); out[o + 1] = clamp(g); out[o + 2] = clamp(b);
            out[o + 3] = Math.round(a * 255);
        }
    }
    return { w: OW, h: OH, px: out };
}

/** Vero se l'immagine e' pixel art: alfa tutto o niente, pochi colori. */
function isPixelArt(px, w, h) {
    const alphas = new Set(), colours = new Set();
    for (let i = 0; i < w * h; i++) {
        alphas.add(px[i * 4 + 3]);
        if (px[i * 4 + 3] > 8) colours.add((px[i * 4] << 16) | (px[i * 4 + 1] << 8) | px[i * 4 + 2]);
    }
    let partial = 0;
    for (const a of alphas) if (a > 8 && a < 248) partial++;
    return partial === 0 && colours.size <= 64;
}

/** Scale2x / EPX: raddoppia arrotondando le diagonali, senza colori nuovi. */
function epx(src, w, h) {
    const W = w * 2, H = h * 2;
    const out = Buffer.alloc(W * H * 4);
    const at = (x, y) => {
        x = Math.max(0, Math.min(w - 1, x));
        y = Math.max(0, Math.min(h - 1, y));
        return src.readUInt32LE((y * w + x) * 4);
    };
    const put = (x, y, v) => out.writeUInt32LE(v, (y * W + x) * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const P = at(x, y), A = at(x, y - 1), B = at(x + 1, y), C = at(x - 1, y), D = at(x, y + 1);
        put(x * 2,     y * 2,     (C === A && C !== D && A !== B) ? A : P);
        put(x * 2 + 1, y * 2,     (A === B && A !== C && B !== D) ? B : P);
        put(x * 2,     y * 2 + 1, (D === C && D !== B && C !== A) ? C : P);
        put(x * 2 + 1, y * 2 + 1, (B === D && B !== A && D !== C) ? D : P);
    }
    return { w: W, h: H, px: out };
}

/** Ingrandisce fino ad almeno `side`, raddoppiando; poi ritaglia col vicino
 *  piu' prossimo se serve una misura che non e' una potenza di due. */
function grow(src, w, h, side) {
    let cur = { w, h, px: src };
    while (Math.max(cur.w, cur.h) * 2 <= side) cur = epx(cur.px, cur.w, cur.h);
    if (Math.max(cur.w, cur.h) === side) return cur;
    // l'ultimo passo col vicino piu' prossimo: su pixel art e' l'unico modo di
    // arrivare a una misura qualunque senza sfocare
    const s = side / Math.max(cur.w, cur.h);
    const OW = Math.round(cur.w * s), OH = Math.round(cur.h * s);
    const out = Buffer.alloc(OW * OH * 4);
    for (let y = 0; y < OH; y++) for (let x = 0; x < OW; x++) {
        const sx = Math.min(cur.w - 1, Math.floor(x / s)), sy = Math.min(cur.h - 1, Math.floor(y / s));
        out.writeUInt32LE(cur.px.readUInt32LE((sy * cur.w + sx) * 4), (y * OW + x) * 4);
    }
    return { w: OW, h: OH, px: out };
}

// --- estrazione ----------------------------------------------------------
const files = fs.readdirSync(PACKS).filter(n => n.endsWith('.pack'));
const found = {};

for (const f of files) {
    let pages;
    try { pages = readPack(path.join(PACKS, f)); } catch (e) { continue; }
    for (const pg of pages) {
        for (const e of pg.entries) {
            const wanted = NAMES.length ? NAMES.includes(e.name) : /pen(cil)?$/i.test(e.name);
            if (!wanted || found[e.name]) continue;
            found[e.name] = { pack: f, page: pg, entry: e };
        }
    }
}

if (Object.keys(found).length === 0) {
    console.log('niente trovato. Prova senza nomi per vedere che cosa somiglia a "Pen".');
    process.exit(1);
}

fs.mkdirSync(OUT, { recursive: true });
for (const [name, hit] of Object.entries(found)) {
    const e = hit.entry;
    const page = decodePNG(hit.page.png);

    // si rimette il ritaglio nel riquadro originale, al suo posto
    const box = Buffer.alloc(e.ow * e.oh * 4);
    for (let y = 0; y < e.h; y++) for (let x = 0; x < e.w; x++) {
        const s = ((e.y + y) * page.w + (e.x + x)) * 4;
        const d = ((e.oy + y) * e.ow + (e.ox + x)) * 4;
        if (e.oy + y >= e.oh || e.ox + x >= e.ow) continue;
        box[d] = page.rgba[s]; box[d + 1] = page.rgba[s + 1];
        box[d + 2] = page.rgba[s + 2]; box[d + 3] = page.rgba[s + 3];
    }

    // Anche alla misura originale: e' la sorgente vera, e permette di rifare
    // l'ingrandimento in un altro modo senza ripassare dal pacchetto.
    writePNG(path.join(OUT, name + '_originale.png'), e.ow, e.oh, box);

    const pixel = isPixelArt(box, e.ow, e.oh);
    const big = pixel ? grow(box, e.ow, e.oh, SIDE)
                      : upscale(box, e.ow, e.oh, SIDE / Math.max(e.ow, e.oh));
    writePNG(path.join(OUT, name + '.png'), big.w, big.h, big.px);
    console.log(`${name.padEnd(18)} da ${hit.pack} / ${hit.page.name}  ${e.ow}x${e.oh} -> ${big.w}x${big.h}`
        + (pixel ? '  (pixel art, EPX)' : '  (sfumata, bicubica)'));
}
console.log('\nscritte in ' + OUT);
