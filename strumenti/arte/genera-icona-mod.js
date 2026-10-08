/*  genera-icona-mod.js - icon.png e poster.png della mod.

    L'icona segue la ricetta delle altre tre di casa (XP Drop, Equipment,
    Hairstyler): quadrato molto stondato, riempimento arancione PIATTO, anello
    bianco, glifo bianco al centro. Qui il glifo e' la
    penna, presa dalla mod stessa - la stessa Pen.png che il pannello mostra
    sul tasto del disegno a mano libera, cosi' l'icona dice esattamente cosa
    apre.

    Le misure non sono stimate: sono state lette dalle tre icone esistenti
    scandendole pixel per pixel, e stanno nella tabella qui sotto.

    Uso:  node MOD/ProjectWriting/strumenti/arte/genera-icona-mod.js
*/
const fs = require('fs'), zlib = require('zlib'), path = require('path');

// --- PNG ---------------------------------------------------------------
let T = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; T[n] = c; }
const crc = b => { let c = 0xFFFFFFFF; for (const x of b) c = T[(c ^ x) & 0xFF] ^ (c >>> 8); return c ^ 0xFFFFFFFF; };

function readPNG(file) {
    const b = fs.readFileSync(file); let p = 8, idat = [], w, h, ct;
    while (p < b.length) {
        const len = b.readUInt32BE(p), t = b.toString('latin1', p + 4, p + 8);
        if (t === 'IHDR') { w = b.readUInt32BE(p + 8); h = b.readUInt32BE(p + 12); ct = b[p + 17]; }
        if (t === 'IDAT') idat.push(b.slice(p + 8, p + 8 + len));
        p += 12 + len;
    }
    const raw = zlib.inflateSync(Buffer.concat(idat));
    const ch = { 0: 1, 2: 3, 4: 2, 6: 4 }[ct], stride = w * ch;
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
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const i = y * stride + x * ch, o = (y * w + x) * 4;
        rgba[o] = out[i];
        rgba[o + 1] = ch >= 3 ? out[i + 1] : out[i];
        rgba[o + 2] = ch >= 3 ? out[i + 2] : out[i];
        rgba[o + 3] = ch === 4 ? out[i + 3] : (ch === 2 ? out[i + 1] : 255);
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

// --- la forma ----------------------------------------------------------
/** Distanza firmata da un rettangolo ad angoli tondi. */
function sdRoundBox(px, py, bx, by, r) {
    const qx = Math.abs(px) - bx + r, qy = Math.abs(py) - by + r;
    return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
}
const clamp01 = v => v < 0 ? 0 : v > 1 ? 1 : v;
const mix = (a, b, t) => a + (b - a) * t;

// Le tre icone esistenti, misurate pixel per pixel a 256x256:
//
//                margine  anello  riempimento          glifo
//   hairstyler      8       12     [238,119,63]     171x172  5971 px
//   equipment       7       13     [236,132,76]     145x163  7274 px
//   xp drop         7       13     [237,130,74]     139x 85  5279 px
//
// Il riempimento e' PIATTO: campionato in alto e in basso da' lo stesso valore
// a un'unita'. La sfumatura diagonale che avevo messo era un'invenzione, ed e'
// la ragione per cui la nostra si distingueva dalle altre a colpo d'occhio.
const FILL = [237, 131, 75];   // Equipment e XP Drop, che coincidono

/** L'icona, a qualunque misura: proporzioni prese dalle tre esistenti. */
function icon(size, glyph, glyphScale) {
    const c = size / 2;
    const half = size * 0.4727;     // margine 7 su 256
    const radius = size * 0.2656;   // 68
    const border = size * 0.0508;   // anello 13
    const px = Buffer.alloc(size * size * 4);

    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        const d = sdRoundBox(x + 0.5 - c, y + 0.5 - c, half, half, radius);
        const outside = clamp01(0.5 - d);           // dentro il bordo bianco
        if (outside <= 0) continue;
        const inside = clamp01(0.5 - (d + border)); // dentro l'arancione

        const o = (y * size + x) * 4;
        px[o] = mix(255, FILL[0], inside);
        px[o + 1] = mix(255, FILL[1], inside);
        px[o + 2] = mix(255, FILL[2], inside);
        px[o + 3] = Math.round(outside * 255);
    }

    // Il glifo, bianco, centrato.
    //
    // Pen.png e' disegnata di contorno per vivere a 34 px su un tasto, quindi
    // ha un tratto sottile. La si porta al peso degli altri glifi ingrandendola,
    // non ingrossandola: dilatare il contorno chiudeva i vuoti interni - la
    // fessura del pennino e la clip sparivano - mentre la scala fa crescere il
    // tratto insieme alla forma. La dilatazione resta di un pixel, per togliere
    // la scalettatura.
    const gs = Math.round(size * glyphScale);
    const grow = 1;
    const ox = Math.round((size - gs) / 2), oy = Math.round((size - gs) / 2);
    const alphaAt = (x, y) => {
        if (x < 0 || y < 0 || x >= gs || y >= gs) return 0;
        const sx = Math.min(glyph.w - 1, Math.floor(x / gs * glyph.w));
        const sy = Math.min(glyph.h - 1, Math.floor(y / gs * glyph.h));
        return glyph.rgba[(sy * glyph.w + sx) * 4 + 3] / 255;
    };
    for (let y = 0; y < gs; y++) for (let x = 0; x < gs; x++) {
        let a = 0;
        for (let dy = -grow; dy <= grow && a < 1; dy++) {
            for (let dx = -grow; dx <= grow && a < 1; dx++) {
                if (dx * dx + dy * dy > grow * grow) continue;
                const v = alphaAt(x + dx, y + dy);
                if (v > a) a = v;
            }
        }
        if (a <= 0) continue;
        const o = ((oy + y) * size + ox + x) * 4;
        px[o] = mix(px[o], 255, a);
        px[o + 1] = mix(px[o + 1], 255, a);
        px[o + 2] = mix(px[o + 2], 255, a);
        px[o + 3] = Math.max(px[o + 3], Math.round(a * 255));
    }
    return px;
}

const MOD = path.join(__dirname, '..', '..', 'workshop', 'Contents', 'mods',
    'ProjectWriting', '42.20');
const pen = readPNG(path.join(MOD, 'media', 'ui', 'NeatWriting', 'Pen.png'));

writePNG(path.join(MOD, 'icon.png'), 256, 256, icon(256, pen, 0.85));
console.log('icon.png    256x256');

/*  --- il poster -------------------------------------------------------

    Il poster NON si genera qui, e questo script non deve toccarlo: e' gia'
    composto in "Project Writing/preview.jpg", 1080x1080 - il personaggio che
    scrive, il libro con il titolo, la firma. Una versione fatta da noi l'aveva
    sovrascritto una volta; non deve succedere di nuovo.

    Node non decodifica il JPEG, quindi la conversione a 512 passa da .NET.
    Da PowerShell, in una riga sola per riga:

      Add-Type -AssemblyName System.Drawing
      $src = [System.Drawing.Image]::FromFile("<progetto>\Project Writing\preview.jpg")
      $bmp = New-Object System.Drawing.Bitmap 512, 512
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, 512, 512))
      $bmp.Save("<mod>\42.20\poster.png", [System.Drawing.Imaging.ImageFormat]::Png)

    Poi poster.png si copia in workshop/preview.png: sono lo stesso file (regola
    del Workshop) e il limite Steam per l'anteprima e' 1 MB - il nostro sta a
    536 KB.
*/
