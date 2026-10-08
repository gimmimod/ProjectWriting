/*  peso-tratti.js - quanto pesa un disegno a mano libera.
 *
 *  Il limite che conta non e' nostro: un oggetto del giocatore, salvato nel
 *  database, si ferma a 2.097.152 byte, e l'inventario ci sta dentro. I nostri
 *  tratti stanno nella modData dell'oggetto, quindi ci vanno a finire anche
 *  loro. Draw On Map quel muro lo prende disegnando con migliaia di simboli;
 *  noi disegniamo in un altro modo, e la domanda "quanto ci manca" non ha mai
 *  avuto un numero.
 *
 *  Questo strumento gliene da' uno. Rifa' fuori dal gioco la catena vera -
 *  cattura adattiva, poi Douglas-Peucker, poi (sulla pagina) una passata di
 *  Chaikin - su tratti finti ma verosimili, e conta punti e byte.
 *
 *  LE COSTANTI SI LEGGONO DA NW_Brush.lua, non si copiano: se domani cambia
 *  RDP_FACTOR, cambia anche questa misura. L'algoritmo invece e' riscritto qui
 *  in JavaScript, e quello si', e' una copia: se si tocca la matematica del
 *  pennello va toccata anche qui, o i due conti divergono in silenzio.
 *
 *      node MOD/ProjectWriting/strumenti/controlli/peso-tratti.js
 */
const fs = require('fs'), path = require('path');

const BRUSH = path.join(__dirname, '..', '..', 'workshop', 'Contents', 'mods',
    'ProjectWriting', '42.20', 'media', 'lua', 'client', 'NeatWriting', 'NW_Brush.lua');

// --- le costanti vere --------------------------------------------------------
const lua = fs.readFileSync(BRUSH, 'utf8');
function costante(nome) {
    const m = lua.match(new RegExp('local\\s+' + nome + '\\s*=\\s*([0-9.]+)'));
    if (!m) throw new Error('non trovo ' + nome + ' in NW_Brush.lua');
    return parseFloat(m[1]);
}
const MIN_DIST = costante('MIN_DIST');
const ANGLE_COS = costante('ANGLE_COS');
const RDP_FACTOR = costante('RDP_FACTOR');

// --- la catena, come nel pennello -------------------------------------------
const dist = (ax, ay, bx, by) => Math.hypot(bx - ax, by - ay);

function perpDist(px, py, ax, ay, bx, by) {
    const dx = bx - ax, dy = by - ay;
    const len2 = dx * dx + dy * dy;
    if (len2 === 0) return dist(px, py, ax, ay);
    let t = ((px - ax) * dx + (py - ay) * dy) / len2;
    t = Math.max(0, Math.min(1, t));
    return dist(px, py, ax + t * dx, ay + t * dy);
}

/** La cattura: un punto entra se e' lontano abbastanza, o se la mano ha girato. */
function cattura(grezzi) {
    const pts = [];
    for (const [x, y] of grezzi) {
        const n = pts.length / 2;
        if (n === 0) { pts.push(x, y); continue; }
        const lx = pts[n * 2 - 2], ly = pts[n * 2 - 1];
        const d = dist(lx, ly, x, y);
        if (d < 0.5) continue;
        let take = d >= MIN_DIST;
        if (!take && n >= 2) {
            const px = pts[n * 2 - 4], py = pts[n * 2 - 3];
            const d1 = dist(px, py, lx, ly);
            if (d1 > 0) {
                const c = ((lx - px) * (x - lx) + (ly - py) * (y - ly)) / (d1 * d);
                if (c < ANGLE_COS) take = true;
            }
        }
        if (take) pts.push(x, y);
    }
    return pts;
}

function simplify(pts, eps) {
    const n = pts.length / 2;
    if (n < 3) return pts;
    const keep = new Array(n).fill(false);
    keep[0] = keep[n - 1] = true;
    const stack = [[0, n - 1]];
    while (stack.length) {
        const [first, last] = stack.pop();
        let maxD = -1, idx = -1;
        const ax = pts[first * 2], ay = pts[first * 2 + 1];
        const bx = pts[last * 2], by = pts[last * 2 + 1];
        for (let i = first + 1; i < last; i++) {
            const d = perpDist(pts[i * 2], pts[i * 2 + 1], ax, ay, bx, by);
            if (d > maxD) { maxD = d; idx = i; }
        }
        if (maxD > eps && idx > 0) {
            keep[idx] = true;
            stack.push([first, idx], [idx, last]);
        }
    }
    const out = [];
    for (let i = 0; i < n; i++) if (keep[i]) out.push(pts[i * 2], pts[i * 2 + 1]);
    return out;
}

/** Chaikin, una passata: quello che la pagina salva dopo aver semplificato. */
function smooth(pts) {
    const n = pts.length / 2;
    if (n < 3) return pts;
    const out = [pts[0], pts[1]];
    for (let i = 0; i < n - 1; i++) {
        const ax = pts[i * 2], ay = pts[i * 2 + 1];
        const bx = pts[i * 2 + 2], by = pts[i * 2 + 3];
        out.push(ax + (bx - ax) * 0.25, ay + (by - ay) * 0.25);
        out.push(ax + (bx - ax) * 0.75, ay + (by - ay) * 0.75);
    }
    out.push(pts[n * 2 - 2], pts[n * 2 - 1]);
    return out;
}

// --- i tratti finti, verosimili ----------------------------------------------
//
// Il mouse manda una posizione a fotogramma: a mano ferma sono pochi pixel di
// passo, e la mano trema sempre un po'. Tre gesti diversi, perche' il costo di
// un cerchio non e' quello di una riga dritta.
let seed = 12345;
function rnd() { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; }

function gesto(tipo, lunghezza, passo, tremore) {
    const out = [];
    for (let t = 0; t < lunghezza; t += passo) {
        let x, y;
        if (tipo === 'riga') { x = t; y = 0; }
        else if (tipo === 'cerchio') {
            const a = (t / lunghezza) * Math.PI * 2;
            x = Math.cos(a) * 120; y = Math.sin(a) * 120;
        } else { // scarabocchio
            x = t * 0.6 + Math.sin(t / 9) * 40;
            y = Math.sin(t / 5) * 30 + Math.cos(t / 17) * 25;
        }
        out.push([x + (rnd() - 0.5) * tremore, y + (rnd() - 0.5) * tremore]);
    }
    return out;
}

// --- la misura ---------------------------------------------------------------
const BYTE_PER_NUMERO = 8;    // un double; prudente, il vero formato e' del motore
const OVERHEAD_TRATTO = 40;   // w, c, la tabella e la sua chiave
const LIMITE = 2097152;

console.log('costanti lette da NW_Brush.lua: MIN_DIST ' + MIN_DIST
    + ', ANGLE_COS ' + ANGLE_COS + ', RDP_FACTOR ' + RDP_FACTOR + '\n');

const larghezze = [1.0, 3.0, 9.0];   // NW.BRUSH MIN, DEFAULT, MAX
const gesti = [
    ['riga dritta   ', gesto('riga', 600, 3, 1.5)],
    ['cerchio       ', gesto('cerchio', 760, 3, 1.5)],
    ['scarabocchio  ', gesto('scarabocchio', 900, 3, 2.0)],
];

console.log('gesto            spessore  grezzi  catturati  dopo RDP  +Chaikin   byte/tratto');
console.log('-'.repeat(84));

let peggiore = 0;
for (const [nome, grezzi] of gesti) {
    for (const w of larghezze) {
        const catturati = cattura(grezzi);
        const dopo = simplify(catturati, w * RDP_FACTOR);
        const conChaikin = smooth(dopo);
        const bytePagina = conChaikin.length * BYTE_PER_NUMERO + OVERHEAD_TRATTO;
        peggiore = Math.max(peggiore, bytePagina);
        console.log(nome + '   ' + String(w).padStart(5) + '   '
            + String(grezzi.length).padStart(6)
            + String(catturati.length / 2).padStart(11)
            + String(dopo.length / 2).padStart(10)
            + String(conChaikin.length / 2).padStart(10)
            + String(bytePagina).padStart(14));
    }
}

console.log('\nIl "+Chaikin" e\' quello che finisce nell\'oggetto SULLA PAGINA');
console.log('(NW_PageInk lisci a una volta e salva il lisciato); sulla mappa si');
console.log('salva la colonna "dopo RDP" e il lisciato si rifa\' al disegno.\n');

const perTratto = peggiore;
console.log('tetto del motore per un oggetto del giocatore: ' + LIMITE.toLocaleString('it-IT') + ' byte');
console.log('tratto piu\' pesante misurato qui:              ' + perTratto.toLocaleString('it-IT') + ' byte');
console.log('tratti prima del muro, se l\'oggetto avesse solo quelli: '
    + Math.floor(LIMITE / perTratto).toLocaleString('it-IT'));
console.log('\nUn oggetto porta anche altro (pagine, nome, il resto della modData),');
console.log('quindi il tetto vero va tenuto ben sotto: la meta\' e\' gia\' prudente.');
