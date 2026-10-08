// Generatore delle icone di Project Writing.
//
//   node MOD/ProjectWriting/strumenti/arte/genera-icone.js
//
// Disegna con distanze firmate e antialiasing analitico: niente supersampling,
// niente scalettature. Ogni tratto ha le estremita' arrotondate (capsule) e le
// punte sono triangoli con gli angoli smussati, cosi' le icone reggono anche a
// 34 px, che e' la misura a cui il pannello le mostra davvero.
//
// Le icone escono bianche su trasparente: e' lo stile Neat, il pannello le
// tinge (NEATUI/CONOSCENZA/STILE.md).
//
// QUI STANNO SOLO LE ICONE CHE DISEGNIAMO NOI. Rotate.png e Resize.png sono
// dell'utente e stanno in "Project Writing/NUOVE ICONE WRITING": erano anche
// qui dentro, e rilanciare il generatore per aggiungere il sole se l'e'
// mangiate. Se serve una nuova icona e ne esiste gia' una in quella cartella,
// si copia quella - non si ridisegna.

const fs = require('fs'), zlib = require('zlib'), path = require('path');

// --- PNG ---------------------------------------------------------------
let CRC = [];
for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; CRC[n] = c; }
const crc32 = b => { let c = 0xFFFFFFFF; for (const x of b) c = CRC[(c ^ x) & 0xFF] ^ (c >>> 8); return c ^ 0xFFFFFFFF; };

function writePNG(file, w, h, px) {
    const stride = w * 4 + 1, raw = Buffer.alloc(h * stride);
    for (let y = 0; y < h; y++) { raw[y * stride] = 0; px.copy(raw, y * stride + 1, y * w * 4, (y + 1) * w * 4); }
    const chunk = (t, d) => {
        const l = Buffer.alloc(4); l.writeUInt32BE(d.length);
        const td = Buffer.concat([Buffer.from(t, 'latin1'), d]);
        const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td) >>> 0);
        return Buffer.concat([l, td, c]);
    };
    const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 6;
    fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
        chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]));
}

// --- distanze firmate --------------------------------------------------
const dot = (ax, ay, bx, by) => ax * bx + ay * by;
const clamp01 = v => v < 0 ? 0 : v > 1 ? 1 : v;

// Capsula: segmento con estremita' arrotondate.
function sdSegment(px, py, ax, ay, bx, by, r) {
    const pax = px - ax, pay = py - ay, bax = bx - ax, bay = by - ay;
    const h = clamp01(dot(pax, pay, bax, bay) / (dot(bax, bay, bax, bay) || 1));
    return Math.hypot(pax - bax * h, pay - bay * h) - r;
}

// Triangolo pieno; `round` smussa gli angoli.
function sdTriangle(px, py, p0, p1, p2, round) {
    const e0 = [p1[0] - p0[0], p1[1] - p0[1]], v0 = [px - p0[0], py - p0[1]];
    const e1 = [p2[0] - p1[0], p2[1] - p1[1]], v1 = [px - p1[0], py - p1[1]];
    const e2 = [p0[0] - p2[0], p0[1] - p2[1]], v2 = [px - p2[0], py - p2[1]];
    const pq0 = [v0[0] - e0[0] * clamp01(dot(v0[0], v0[1], e0[0], e0[1]) / dot(e0[0], e0[1], e0[0], e0[1])),
                 v0[1] - e0[1] * clamp01(dot(v0[0], v0[1], e0[0], e0[1]) / dot(e0[0], e0[1], e0[0], e0[1]))];
    const pq1 = [v1[0] - e1[0] * clamp01(dot(v1[0], v1[1], e1[0], e1[1]) / dot(e1[0], e1[1], e1[0], e1[1])),
                 v1[1] - e1[1] * clamp01(dot(v1[0], v1[1], e1[0], e1[1]) / dot(e1[0], e1[1], e1[0], e1[1]))];
    const pq2 = [v2[0] - e2[0] * clamp01(dot(v2[0], v2[1], e2[0], e2[1]) / dot(e2[0], e2[1], e2[0], e2[1])),
                 v2[1] - e2[1] * clamp01(dot(v2[0], v2[1], e2[0], e2[1]) / dot(e2[0], e2[1], e2[0], e2[1]))];
    const s = Math.sign(e0[0] * e2[1] - e0[1] * e2[0]);
    const d = Math.min(
        Math.min(dot(pq0[0], pq0[1], pq0[0], pq0[1]), s * (v0[0] * e0[1] - v0[1] * e0[0])) === dot(pq0[0], pq0[1], pq0[0], pq0[1])
            ? dot(pq0[0], pq0[1], pq0[0], pq0[1]) : dot(pq0[0], pq0[1], pq0[0], pq0[1]),
        dot(pq1[0], pq1[1], pq1[0], pq1[1]), dot(pq2[0], pq2[1], pq2[0], pq2[1]));
    const sign = Math.min(s * (v0[0] * e0[1] - v0[1] * e0[0]),
                          Math.min(s * (v1[0] * e1[1] - v1[1] * e1[0]), s * (v2[0] * e2[1] - v2[1] * e2[0])));
    return -Math.sqrt(d) * Math.sign(sign) - (round || 0);
}

// --- canvas ------------------------------------------------------------
function icon(size, build) {
    const shapes = [];
    const api = {
        // Tratto con estremita' tonde.
        line(x0, y0, x1, y1, w) { shapes.push(p => sdSegment(p[0], p[1], x0, y0, x1, y1, w / 2)); },
        // Punta di freccia piena, smussata, che guarda in (dx,dy).
        head(tx, ty, dx, dy, len, half) {
            const a = Math.atan2(dy, dx), r = 2.2;
            const bx = tx - Math.cos(a) * len, by = ty - Math.sin(a) * len;
            const nx = -Math.sin(a) * half, ny = Math.cos(a) * half;
            shapes.push(p => sdTriangle(p[0], p[1],
                [tx, ty], [bx + nx, by + ny], [bx - nx, by - ny], r));
        },
        arc(cx, cy, r, a0, a1, w) {
            const n = Math.max(24, Math.ceil(Math.abs(a1 - a0) * r / 2));
            for (let i = 0; i < n; i++) {
                const t0 = a0 + (a1 - a0) * i / n, t1 = a0 + (a1 - a0) * (i + 1) / n;
                this.line(cx + Math.cos(t0) * r, cy + Math.sin(t0) * r,
                          cx + Math.cos(t1) * r, cy + Math.sin(t1) * r, w);
            }
        },
        // Riquadro a spigoli arrotondati, solo contorno.
        frame(x0, y0, x1, y1, w, r) {
            this.line(x0 + r, y0, x1 - r, y0, w);
            this.line(x0 + r, y1, x1 - r, y1, w);
            this.line(x0, y0 + r, x0, y1 - r, w);
            this.line(x1, y0 + r, x1, y1 - r, w);
            this.arc(x0 + r, y0 + r, r, Math.PI, Math.PI * 1.5, w);
            this.arc(x1 - r, y0 + r, r, Math.PI * 1.5, Math.PI * 2, w);
            this.arc(x1 - r, y1 - r, r, 0, Math.PI * 0.5, w);
            this.arc(x0 + r, y1 - r, r, Math.PI * 0.5, Math.PI, w);
        },
    };
    build(api);

    const out = Buffer.alloc(size * size * 4);
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        const p = [x + 0.5, y + 0.5];
        let d = 1e9;
        for (const s of shapes) { const v = s(p); if (v < d) d = v; }
        // Antialiasing analitico su un pixel di transizione.
        const a = Math.max(0, Math.min(1, 0.5 - d));
        const o = (y * size + x) * 4;
        out[o] = 255; out[o + 1] = 255; out[o + 2] = 255; out[o + 3] = Math.round(a * 255);
    }
    return out;
}

// --- le icone ----------------------------------------------------------
const S = 128, C = 64, W = 9, HL = 24, HW = 13;
const OUT = path.join(__dirname, '..', '..', 'workshop', 'Contents', 'mods',
    'ProjectWriting', '42.20', 'media', 'ui', 'NeatWriting');

const ICONS = {
    'Move.png': a => {
        a.line(C, 30, C, 98, W); a.line(30, C, 98, C, W);
        a.head(C, 16, 0, -1, HL, HW); a.head(C, 112, 0, 1, HL, HW);
        a.head(16, C, -1, 0, HL, HW); a.head(112, C, 1, 0, HL, HW);
    },
    // Sole: cerchio vuoto e otto raggi. Il riferimento e' molto piu' sottile di
    // cosi', ma questa icona vive a 18 px nel pannello impostazioni mappa: un
    // tratto fedele all'originale sparirebbe.
    'Sun.png': a => {
        a.arc(C, C, 26, 0, Math.PI * 2, W);
        for (let i = 0; i < 8; i++) {
            const t = i * Math.PI / 4;
            a.line(C + Math.cos(t) * 40, C + Math.sin(t) * 40,
                   C + Math.cos(t) * 56, C + Math.sin(t) * 56, W);
        }
    },
};

for (const [name, build] of Object.entries(ICONS)) {
    writePNG(path.join(OUT, name), S, S, icon(S, build));
    console.log(name);
}
