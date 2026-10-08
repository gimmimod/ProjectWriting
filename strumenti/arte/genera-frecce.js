// Le due frecce per sfogliare le pagine.
//
//   node MOD/ProjectWriting/strumenti/arte/genera-frecce.js
//
// Sta a parte da genera-icone.js apposta: quello ridisegna tutto quello che
// conosce, e un generatore che riscrive file altrui ha gia' fatto danni una
// volta. Questo tocca due nomi, e solo quelli.
//
// Un galloncino di due capsule, bianco su trasparente come le altre icone
// (128x128, il pannello le tinge). Stesso spessore di tratto di Text.png e
// Move.png, cosi' in fila non stona.

const fs = require('fs'), zlib = require('zlib'), path = require('path');

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

const clamp01 = v => v < 0 ? 0 : v > 1 ? 1 : v;
function segment(px, py, ax, ay, bx, by, r) {
    const pax = px - ax, pay = py - ay, bax = bx - ax, bay = by - ay;
    const den = bax * bax + bay * bay || 1;
    const h = clamp01((pax * bax + pay * bay) / den);
    return Math.hypot(pax - bax * h, pay - bay * h) - r;
}

const S = 128, R = 9;          // lato, e mezzo spessore del tratto
const TIP = 40, BACK = 84;     // dove sta la punta e dove tornano i bracci
const TOP = 30, BOT = 98;

function chevron(file, left) {
    const px = Buffer.alloc(S * S * 4);
    const tipX = left ? TIP : S - TIP;
    const backX = left ? BACK : S - BACK;
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
        const cx = x + 0.5, cy = y + 0.5;
        const d = Math.min(
            segment(cx, cy, backX, TOP, tipX, S / 2, R),
            segment(cx, cy, backX, BOT, tipX, S / 2, R));
        const a = clamp01(0.5 - d);        // antialiasing analitico, un pixel
        const o = (y * S + x) * 4;
        px[o] = 255; px[o + 1] = 255; px[o + 2] = 255; px[o + 3] = Math.round(a * 255);
    }
    writePNG(file, S, S, px);
    console.log('scritto ' + path.basename(file));
}

const OUT = path.join(__dirname, '..', '..', 'workshop', 'Contents', 'mods',
    'ProjectWriting', '42.20', 'media', 'ui', 'NeatWriting');
chevron(path.join(OUT, 'Arrow_Left.png'), true);
chevron(path.join(OUT, 'Arrow_Right.png'), false);
