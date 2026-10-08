/*  png.js - leggere e scrivere PNG a mano, perche' qui non c'e' una libreria.

    Lo stesso lettore e lo stesso scrittore che stavano copiati in fondo a ogni
    strumento di questa cartella. Sono un PNG minimo ma completo per quello che
    serve: si leggono le otto immagini della carta (tavolozza, grigi, RGBA) e si
    scrivono le anteprime in RGBA a 8 bit.
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
const SRC = path.join(__dirname, '..', '..', '..', '..', 'Project Writing', 'canvas');

module.exports = { readPNG, writePNG };
