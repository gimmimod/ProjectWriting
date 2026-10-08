/*  anteprima-slot.js - le caselle degli strumenti come le disegna il gioco.

    Le caselle del pannello sono lo slot di Clean HotBar tinto col colore
    dell'inchiostro (NW_Style.drawSlot). Un numero di colore non dice come
    appare: dietro una texture a meta' trasparenza, su un pannello scuro, con
    il bagliore al centro e l'icona dell'oggetto sopra. Alla prima prova il nero
    a 0.16 era identico alla casella vuota di una gomma, e la grafite sembrava
    una casella spenta - e dal codice non si vedeva.

    Qui la casella si ricompone come fa il motore: texel per tinta, alfa per
    alfa, SRC_ALPHA / ONE_MINUS_SRC_ALPHA, texture ridotte ad area, colonne
    ritagliate come fa lo stencil. I colori si leggono da NW_Config.lua (il
    campo `slot` di ogni inchiostro), le texture da workshop/, le icone vere
    del gioco da art/sorgenti/oggetti-gioco/ (32x32, estratte con
    estrai-icona.js). La regola del disegno e' ricopiata da NW_Style.drawSlot:
    se cambia li', va cambiata anche qui.

    Esce art/anteprime/anteprima-slot.png, ingrandita tre volte senza filtro:
    prima riga a riposo, in mano, sotto il mouse; seconda riga la penna
    multicolore in mano, la matita girata sulla gomma, i pastelli, il pennarello.

    Uso:  node MOD/ProjectWriting/strumenti/arte/anteprima-slot.js
*/
const fs = require('fs'), path = require('path');
const { readPNG, writePNG } = require('../controlli/png.js');

const MOD = path.join(__dirname, '..', '..');
const UI = path.join(MOD, 'workshop', 'Contents', 'mods', 'ProjectWriting', '42.20', 'media', 'ui', 'NeatWriting');
const CONFIG = path.join(MOD, 'workshop', 'Contents', 'mods', 'ProjectWriting', '42.20', 'media', 'lua', 'client', 'NeatWriting', 'NW_Config.lua');
const ICONE = path.join(MOD, 'art', 'sorgenti', 'oggetti-gioco');
const OUT = path.join(MOD, 'art', 'anteprime', 'anteprima-slot.png');

// --- i colori, da NW_Config.lua ----------------------------------------------
const INK = {};
{
    const lua = fs.readFileSync(CONFIG, 'utf8');
    const re = /id = "(\w+)"[\s\S]*?slot = \{ r = ([\d.]+), g = ([\d.]+), b = ([\d.]+) \}/g;
    let m;
    while ((m = re.exec(lua))) INK[m[1]] = { r: +m[2], g: +m[3], b: +m[4] };
    for (const id of ['black', 'pencil', 'red', 'blue', 'green']) {
        if (!INK[id]) { console.error('in NW_Config.lua manca il colore slot di ' + id); process.exit(1); }
    }
}

// --- immagini -----------------------------------------------------------------
function rgba(file) {
    const im = readPNG(file), n = im.w * im.h, ch = im.rgba.length / n;
    if (ch === 4) return im;
    const o = Buffer.alloc(n * 4);
    for (let i = 0; i < n; i++) {
        const s = i * ch;
        o[i * 4] = im.rgba[s]; o[i * 4 + 1] = im.rgba[s + (ch >= 3 ? 1 : 0)]; o[i * 4 + 2] = im.rgba[s + (ch >= 3 ? 2 : 0)];
        o[i * 4 + 3] = ch === 2 ? im.rgba[s + 1] : 255;
    }
    return { w: im.w, h: im.h, rgba: o };
}

/** Riduzione ad area, in alfa premoltiplicato. */
function scaled(im, w, h) {
    const o = new Float64Array(w * h * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const x0 = x * im.w / w, x1 = (x + 1) * im.w / w, y0 = y * im.h / h, y1 = (y + 1) * im.h / h;
        let r = 0, g = 0, b = 0, a = 0, t = 0;
        for (let sy = Math.floor(y0); sy < Math.ceil(y1); sy++) for (let sx = Math.floor(x0); sx < Math.ceil(x1); sx++) {
            const k = (Math.min(sx + 1, x1) - Math.max(sx, x0)) * (Math.min(sy + 1, y1) - Math.max(sy, y0));
            const i = (sy * im.w + sx) * 4, al = im.rgba[i + 3] / 255;
            r += im.rgba[i] / 255 * al * k; g += im.rgba[i + 1] / 255 * al * k; b += im.rgba[i + 2] / 255 * al * k;
            a += al * k; t += k;
        }
        const j = (y * w + x) * 4;
        o[j + 3] = a / t;
        if (a > 0) { o[j] = r / a; o[j + 1] = g / a; o[j + 2] = b / a; }
    }
    return o;
}

const W = 340, H = 110, Z = 3;
const can = new Float64Array(W * H * 3).fill(0.105);   // il fondo di un riquadro del pannello

function draw(tex, x, y, w, h, a, r, g, b, clip) {
    const px = scaled(tex, w, h);
    for (let yy = 0; yy < h; yy++) for (let xx = 0; xx < w; xx++) {
        const X = x + xx, Y = y + yy;
        if (X < 0 || Y < 0 || X >= W || Y >= H) continue;
        if (clip && (X < clip[0] || X >= clip[0] + clip[1])) continue;
        const j = (yy * w + xx) * 4, al = px[j + 3] * a;
        if (al <= 0) continue;
        const i = (Y * W + X) * 3;
        can[i] = px[j] * r * al + can[i] * (1 - al);
        can[i + 1] = px[j + 1] * g * al + can[i + 1] * (1 - al);
        can[i + 2] = px[j + 2] * b * al + can[i + 2] * (1 - al);
    }
}

const T = {
    bg: rgba(path.join(UI, 'Slot', 'Slot_BG.png')),
    border: rgba(path.join(UI, 'Slot', 'Slot_Border.png')),
    glow: rgba(path.join(UI, 'Slot', 'Slot_Hover.png')),
    badge: rgba(path.join(UI, 'PencilErase.png')),
};
const SELECTION = { r: 0.30, g: 0.72, b: 0.38 }, ACCENT = { r: 0.95, g: 0.50, b: 0.10 };

// --- NW_Style.drawSlot, riga per riga ---------------------------------------------
function drawSlot(x, y, w, h, o) {
    const base = o.hover ? 0.50 : 0.35;
    draw(T.bg, x, y, w, h, 0.6, base, base, base);
    const fills = o.fills || [], n = fills.length;
    if (n > 0 && !o.badge) {
        const strong = o.hover ? 0.95 : 0.85, soft = 0.30, cw = w / n;
        fills.forEach((c, k) => {
            const i = k + 1;
            const a = (n > 1 && o.current && o.current !== i) ? soft : strong;
            let clip = null;
            if (n > 1) {
                const cx0 = Math.floor(x + (i - 1) * cw), cx1 = i === n ? x + w : Math.floor(x + i * cw);
                clip = [cx0, cx1 - cx0];
            }
            draw(T.bg, x, y, w, h, a, c.r, c.g, c.b, clip);
        });
    }
    draw(T.glow, x, y, w, h, 0.6, 0.98, 0.95, 0.85);
    let c = { r: 0.6, g: 0.6, b: 0.6 }, a = 0.6;
    if (o.selected) { c = SELECTION; a = 1.0; } else if (o.hover) { c = ACCENT; a = 0.85; }
    if (o.badge) { const bs = Math.floor(w * 0.42); draw(T.badge, x + w - bs - 2, y + 2, bs, bs, 1, 0.9, 0.9, 0.9); }
    draw(T.border, x, y, w, h, a, c.r, c.g, c.b);
    // L'icona dell'oggetto: NW_Panel:drawSlot, inscritta con il suo margine.
    const icon = rgba(path.join(ICONE, o.icon + '.png'));
    const pad = Math.max(3, Math.floor(w * 0.15)), box = w - pad * 2;
    const k = Math.min(box / icon.w, box / icon.h), dw = Math.floor(icon.w * k), dh = Math.floor(icon.h * k);
    draw(icon, x + Math.floor((w - dw) / 2), y + Math.floor((h - dh) / 2), dw, dh, 1, 1, 1, 1);
}

const SLOT = 40, GAP = 6;
const PEN4 = [INK.black, INK.red, INK.blue, INK.green];
[
    { icon: 'Item_Pen', fills: [INK.black] },
    { icon: 'Item_Pen', fills: [INK.red], selected: true },
    { icon: 'Item_Pen', fills: [INK.blue], hover: true },
    { icon: 'Item_Pen', fills: [INK.green] },
    { icon: 'Item_Pencil', fills: [INK.pencil] },
    { icon: 'Item_Eraser', fills: [] },
    { icon: 'Item_PenMulticolor', fills: PEN4 },
].forEach((o, i) => drawSlot(10 + i * (SLOT + GAP), 10, SLOT, SLOT, o));
[
    { icon: 'Item_PenMulticolor', fills: PEN4, selected: true, current: 2 },
    { icon: 'Item_Pencil', fills: [INK.pencil], selected: true, badge: true },
    { icon: 'Item_Crayons', fills: [INK.black, INK.pencil, INK.red, INK.blue, INK.green] },
    { icon: 'Item_MarkerBlack', fills: [INK.black], hover: true },
].forEach((o, i) => drawSlot(10 + i * (SLOT + GAP), 16 + SLOT + GAP, SLOT, SLOT, o));

const out = Buffer.alloc(W * Z * H * Z * 4);
for (let y = 0; y < H * Z; y++) for (let x = 0; x < W * Z; x++) {
    const i = (Math.floor(y / Z) * W + Math.floor(x / Z)) * 3, j = (y * W * Z + x) * 4;
    for (let c = 0; c < 3; c++) out[j + c] = Math.round(Math.min(1, Math.max(0, can[i + c])) * 255);
    out[j + 3] = 255;
}
writePNG(OUT, W * Z, H * Z, out);
console.log('scritta ' + path.relative(process.cwd(), OUT));
