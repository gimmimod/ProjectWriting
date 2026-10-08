/*  scritta-mano.js - una scritta nella grafia del gioco, come immagine.

    Compone il testo con i glifi veri di UIFont.Handwritten, prendendoli dove
    stanno: media/fonts/handwritten.fnt (le misure) e handwritten_0.png
    (l'atlante). Il carattere e' Caveat SemiBold a 40 px, e nell'atlante i glifi
    stanno nel canale alfa - il colore e' bianco ovunque - quindi si usa l'alfa
    come maschera e ci si dipinge dentro l'inchiostro che si vuole.

    Le crenature ci sono e si applicano: sono 219 coppie, e senza di quelle una
    grafia corsiva si vede subito che e' stata montata a pezzi.

    ALTA RISOLUZIONE DA UN CARATTERE DA 40 PIXEL. Ingrandire una maschera e
    basta da' una scritta fuori fuoco: il bordo, che nell'originale e' largo un
    pixel, diventa largo quanto l'ingrandimento.

    Quindi il bordo si ricostruisce. Dalla maschera si ricava un CAMPO DI
    DISTANZA con segno - per ogni pixel, quanto dista dal bordo della lettera -
    e la copertura antialiasata dell'originale serve a stimare quella distanza
    sotto al pixel, che e' il dettaglio che permette di ingrandire senza
    inventare. Poi si ridisegna alla misura grande interpolando il campo, dove
    un bordo torna a essere largo un pixel.

    E' lo stesso principio dei font SDF che il gioco usa per i nomi delle
    strade, applicato a mano a un carattere che SDF non e'.

    Uso:  node MOD/ProjectWriting/strumenti/arte/scritta-mano.js "Project Writing" [scala] [file]
*/
const fs = require('fs'), zlib = require('zlib'), path = require('path');

const TEXT  = process.argv[2] || 'Project Writing';
const SCALE = Number(process.argv[3]) || 10;
const OUT   = process.argv[4] ||
    path.join(__dirname, '..', '..', '..', '..', 'Project Writing', 'scritta-project-writing.png');

// L'inchiostro matita di NW_Config: NW.INKS[pencil] = 0.200, 0.200, 0.200
const INK = { r: 0.200, g: 0.200, b: 0.200 };

const FONTS = 'C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/media/fonts';
const FNT = path.join(FONTS, 'handwritten.fnt');
const PNG = path.join(FONTS, 'handwritten_0.png');

// --- PNG ---------------------------------------------------------------
let T = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; T[n] = c; }
const crc = b => { let c = 0xFFFFFFFF; for (const x of b) c = T[(c ^ x) & 0xFF] ^ (c >>> 8); return c ^ 0xFFFFFFFF; };

function readPNG(file) {
    const b = fs.readFileSync(file);
    let p = 8, idat = [], w, h, depth, ct, pal = null, trns = null;
    while (p < b.length) {
        const len = b.readUInt32BE(p), t = b.toString('latin1', p + 4, p + 8);
        const d = b.slice(p + 8, p + 8 + len);
        if (t === 'IHDR') { w = b.readUInt32BE(p + 8); h = b.readUInt32BE(p + 12); depth = b[p + 16]; ct = b[p + 17]; }
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
    // solo l'alfa: nell'atlante il colore e' bianco ovunque
    const alpha = new Uint8Array(w * h);
    for (let i = 0; i < w * h; i++) {
        if (ct === 3) { const ix = out[i]; alpha[i] = (trns && ix < trns.length) ? trns[ix] : 255; }
        else if (ct === 6) alpha[i] = out[i * 4 + 3];
        else if (ct === 4) alpha[i] = out[i * 2 + 1];
        else alpha[i] = out[i * chan];
    }
    return { w, h, alpha };
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

// --- il descrittore del carattere ---------------------------------------
function readFNT(file) {
    const chars = {}, kern = {};
    let lineHeight = 40, base = 30, face = '?';
    for (const line of fs.readFileSync(file, 'latin1').split(/\r?\n/)) {
        const f = {};
        for (const m of line.matchAll(/(\w+)=(-?\d+|"[^"]*")/g)) {
            f[m[1]] = m[2].startsWith('"') ? m[2].slice(1, -1) : Number(m[2]);
        }
        if (line.startsWith('info ')) face = f.face;
        else if (line.startsWith('common ')) { lineHeight = f.lineHeight; base = f.base; }
        else if (line.startsWith('char ')) chars[f.id] = f;
        else if (line.startsWith('kerning ')) kern[f.first + ':' + f.second] = f.amount;
    }
    return { chars, kern, lineHeight, base, face };
}

// --- composizione alla misura nativa ------------------------------------
const font = readFNT(FNT);
const atlas = readPNG(PNG);

// margine largo: certi glifi corsivi escono parecchio dal loro riquadro
const PAD = 24;
const codes = [...TEXT].map(c => c.codePointAt(0));

let penX = PAD, width = PAD * 2;
for (let i = 0; i < codes.length; i++) {
    const g = font.chars[codes[i]];
    if (!g) continue;
    if (i > 0) width += font.kern[codes[i - 1] + ':' + codes[i]] || 0;
    width += g.xadvance;
}
width = Math.ceil(width);
const height = font.lineHeight + PAD * 2;

const mask = new Float32Array(width * height);
for (let i = 0; i < codes.length; i++) {
    const g = font.chars[codes[i]];
    if (!g) continue;
    if (i > 0) penX += font.kern[codes[i - 1] + ':' + codes[i]] || 0;
    for (let y = 0; y < g.height; y++) {
        for (let x = 0; x < g.width; x++) {
            const a = atlas.alpha[(g.y + y) * atlas.w + (g.x + x)] / 255;
            if (a <= 0) continue;
            const dx = Math.round(penX + g.xoffset + x);
            const dy = PAD + g.yoffset + y;
            if (dx < 0 || dy < 0 || dx >= width || dy >= height) continue;
            const o = dy * width + dx;
            // i glifi corsivi si toccano: si tiene il piu' coprente, non la somma
            if (a > mask[o]) mask[o] = a;
        }
    }
    penX += g.xadvance;
}

// --- ritaglio sul disegno ------------------------------------------------
let x0 = width, y0 = height, x1 = -1, y1 = -1;
for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    if (mask[y * width + x] > 0.02) {
        if (x < x0) x0 = x; if (x > x1) x1 = x;
        if (y < y0) y0 = y; if (y > y1) y1 = y;
    }
}
const M = 6;   // un filo d'aria attorno
x0 = Math.max(0, x0 - M); y0 = Math.max(0, y0 - M);
x1 = Math.min(width - 1, x1 + M); y1 = Math.min(height - 1, y1 + M);
const cw = x1 - x0 + 1, ch = y1 - y0 + 1;

const crop = new Float32Array(cw * ch);
for (let y = 0; y < ch; y++) for (let x = 0; x < cw; x++) {
    crop[y * cw + x] = mask[(y0 + y) * width + (x0 + x)];
}

// --- campo di distanza con segno ----------------------------------------
// Distanza in pixel dell'originale dal bordo della lettera: positiva dentro,
// negativa fuori.
//
// La distanza e' EUCLIDEA ESATTA, calcolata con la trasformata di Felzenszwalb:
// una passata per righe e una per colonne, ognuna il minimo di un fascio di
// parabole. La prima versione usava i passi interi del chamfer (1 e radice di
// due) e il campo veniva a gradini: ringrandito, ogni gradino diventava una
// tacca sul bordo delle lettere, e la scritta sembrava scheggiata.

const INF = 1e20;

/** Trasformata di distanza quadratica di una riga, in loco. */
function edt1d(f, n, d, v, z) {
    let k = 0;
    v[0] = 0; z[0] = -INF; z[1] = INF;
    for (let q = 1; q < n; q++) {
        let s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
        while (s <= z[k]) {
            k--;
            s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
        }
        k++;
        v[k] = q; z[k] = s; z[k + 1] = INF;
    }
    k = 0;
    for (let q = 0; q < n; q++) {
        while (z[k + 1] < q) k++;
        d[q] = (q - v[k]) * (q - v[k]) + f[v[k]];
    }
}

/** Distanza euclidea da ogni pixel al piu' vicino "acceso". */
function edt(seed, w, h) {
    const f = new Float64Array(Math.max(w, h));
    const d = new Float64Array(Math.max(w, h));
    const v = new Int32Array(Math.max(w, h) + 1);
    const z = new Float64Array(Math.max(w, h) + 1);
    const out = new Float64Array(w * h);

    for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) f[x] = seed[y * w + x] ? 0 : INF;
        edt1d(f, w, d, v, z);
        for (let x = 0; x < w; x++) out[y * w + x] = d[x];
    }
    for (let x = 0; x < w; x++) {
        for (let y = 0; y < h; y++) f[y] = out[y * w + x];
        edt1d(f, h, d, v, z);
        for (let y = 0; y < h; y++) out[y * w + x] = Math.sqrt(d[y]);
    }
    return out;
}

const inside = new Uint8Array(cw * ch);
const outside = new Uint8Array(cw * ch);
for (let i = 0; i < cw * ch; i++) {
    if (crop[i] >= 0.5) inside[i] = 1; else outside[i] = 1;
}
const dIn = edt(outside, cw, ch);    // quanto dista un pixel dentro dal fuori
const dOut = edt(inside, cw, ch);    // e viceversa

const dist = new Float64Array(cw * ch);
for (let i = 0; i < cw * ch; i++) {
    const a = crop[i];
    if (a > 0.02 && a < 0.98) {
        // Sul bordo comanda la copertura: a=0.5 vuol dire contorno esattamente
        // al centro del pixel. E' il mezzo pixel di risoluzione in piu' che
        // permette di ingrandire senza inventare.
        dist[i] = a - 0.5;
    } else if (crop[i] >= 0.5) {
        dist[i] = dIn[i] - 0.5;
    } else {
        dist[i] = -(dOut[i] - 0.5);
    }
}

// Una lisciata leggerissima al campo: toglie il residuo di scalettatura senza
// arrotondare le punte, perche' su un campo di distanza una media pesata
// sposta il contorno di frazioni di pixel e basta.
const smooth = new Float64Array(cw * ch);
for (let y = 0; y < ch; y++) for (let x = 0; x < cw; x++) {
    let s = 0, wsum = 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= cw || ny >= ch) continue;
        const k = (dx === 0 ? 2 : 1) * (dy === 0 ? 2 : 1);
        s += dist[ny * cw + nx] * k; wsum += k;
    }
    smooth[y * cw + x] = s / wsum;
}

// --- si ridisegna alla misura grande ------------------------------------
// Il campo si interpola in modo bilineare - e' continuo, quindi non serve di
// piu' - e la soglia rida' un bordo largo circa un pixel DI ARRIVO, non uno di
// partenza. E' li' che sta la nitidezza.
function fieldAt(fx, fy) {
    const x = Math.max(0, Math.min(cw - 1.001, fx));
    const y = Math.max(0, Math.min(ch - 1.001, fy));
    const ix = Math.floor(x), iy = Math.floor(y);
    const tx = x - ix, ty = y - iy;
    const i0 = iy * cw, i1 = Math.min(ch - 1, iy + 1) * cw;
    const jx = Math.min(cw - 1, ix + 1);
    const a = smooth[i0 + ix], b = smooth[i0 + jx];
    const c = smooth[i1 + ix], d = smooth[i1 + jx];
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
}

const OW = Math.round(cw * SCALE), OH = Math.round(ch * SCALE);
const big = new Float32Array(OW * OH);
const soft = 1.0 / SCALE;    // un pixel di arrivo, in unita di partenza
for (let oy = 0; oy < OH; oy++) {
    const sy = (oy + 0.5) / SCALE - 0.5;
    for (let ox = 0; ox < OW; ox++) {
        const sx = (ox + 0.5) / SCALE - 0.5;
        const v = 0.5 + fieldAt(sx, sy) / soft;
        big[oy * OW + ox] = v < 0 ? 0 : v > 1 ? 1 : v;
    }
}

// --- inchiostro ----------------------------------------------------------
const px = Buffer.alloc(OW * OH * 4);
const R = Math.round(INK.r * 255), G = Math.round(INK.g * 255), B = Math.round(INK.b * 255);
for (let i = 0; i < OW * OH; i++) {
    px[i * 4] = R; px[i * 4 + 1] = G; px[i * 4 + 2] = B;
    px[i * 4 + 3] = Math.round(big[i] * 255);
}

fs.mkdirSync(path.dirname(OUT), { recursive: true });
writePNG(OUT, OW, OH, px);
console.log(`"${TEXT}" in ${font.face} ${font.lineHeight}px`);
console.log(`  composta ${cw}x${ch}, ingrandita ${SCALE}x -> ${OW}x${OH}`);
console.log(`  inchiostro matita ${R},${G},${B} su fondo trasparente`);
console.log(`  scritto ${OUT}`);
