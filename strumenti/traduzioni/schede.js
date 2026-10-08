/*  schede.js - quante tessere ha ogni scheda, per ogni combinazione di
    pacchetti accesi.

    Una tassonomia va bene solo se regge anche quando qualcuno spegne due
    pacchetti su tre: una scheda che resta vuota non deve comparire, e una che
    resta con una tessera sola e' una scheda sprecata.

    Legge NW_Categories.lua, cosi non c'e' una seconda copia della tabella che
    puo' andare fuori sincrono.

    Uso:  node MOD/ProjectWriting/strumenti/traduzioni/schede.js
*/
const fs = require('fs');
const path = require('path');

const LUA = path.join(__dirname, '..', '..', 'workshop', 'Contents', 'mods',
    'ProjectWriting', '42.20', 'media', 'lua', 'shared', 'NeatWriting',
    'NW_Categories.lua');
const src = fs.readFileSync(LUA, 'utf8');

// Le costanti: C.MARKS = "NW_Marks" e compagnia.
const CONST = {};
for (const m of src.matchAll(/^C\.([A-Z_]+)\s*=\s*"([^"]+)"/gm)) CONST[m[1]] = m[2];

// Le abbreviazioni della tabella: local M, P, L, ... = C.MARKS, C.PLACES, ...
const abbrev = {};
const alias = src.match(/local ([\w, ]+) =\n\s*([^\n]+),\n\s*([^\n]+)\n/);
if (alias) {
    const names = alias[1].split(',').map(s => s.trim());
    const values = (alias[2] + ',' + alias[3]).split(',').map(s => s.trim().replace(/^C\./, ''));
    names.forEach((n, i) => { abbrev[n] = CONST[values[i]]; });
}

// La tabella id -> scheda.
const body = src.split('C.OF = {')[1].split(/\n}/)[0];
const OF = {};
for (const m of body.matchAll(/\["([^"]+)"\]\s*=\s*(\w+)/g)) OF[m[1]] = abbrev[m[2]];
for (const m of body.matchAll(/(?:^|[\s,{])([A-Za-z][A-Za-z0-9_]*)\s*=\s*(\w+)(?=\s*[,\n])/g)) {
    if (!(m[1] in abbrev)) OF[m[1]] = abbrev[m[2]];
}

const ORDER = (src.split('C.ORDER = {')[1].split('}')[0])
    .split(',').map(s => s.trim().replace(/^C\./, '')).filter(Boolean).map(k => CONST[k]);

const LABEL = {};
for (const m of src.matchAll(/\[C\.([A-Z_]+)\]\s*=\s*"IGUI_NW_Tab(\w+)"/g)) LABEL[CONST[m[1]]] = m[2];

// Da quale pacchetto viene ogni id: le stesse regole di C.packOf.
const packOf = id =>
    id.startsWith('nw:') ? 'extra' : id.startsWith('AmmS') ? 'amms' : 'vanilla';

const ids = Object.keys(OF);
const PACKS = ['vanilla', 'extra', 'amms'];

let problemi = 0;
console.log('scheda'.padEnd(10) + PACKS.map(p => p.padStart(8)).join('') + '   totale');
console.log('-'.repeat(46));
for (const tab of ORDER) {
    const row = PACKS.map(p =>
        ids.filter(id => OF[id] === tab && packOf(id) === p).length);
    const tot = row.reduce((a, b) => a + b, 0);
    console.log(LABEL[tab].padEnd(10) + row.map(n => String(n).padStart(8)).join('') +
        String(tot).padStart(9));
}

// La piega delle schede magre, la stessa di C.foldThin.
const MIN = Number((src.match(/C\.MIN_TILES\s*=\s*(\d+)/) || [])[1] || 3);
const FALLBACK = {};
for (const m of (src.split('C.FALLBACK = {')[1] || '').split('}')[0]
        .matchAll(/\[C\.([A-Z_]+)\]\s*=\s*C\.([A-Z_]+)/g)) {
    FALLBACK[CONST[m[1]]] = CONST[m[2]];
}

function fold(conta) {
    for (let i = ORDER.length - 1; i >= 0; i--) {
        const tab = ORDER[i], into = FALLBACK[tab];
        if (conta[tab] && into && conta[tab] < MIN) {
            conta[into] = (conta[into] || 0) + conta[tab];
            delete conta[tab];
        }
    }
    return conta;
}

console.log(`\ncombinazioni, dopo la piega delle schede sotto le ${MIN} tessere:`);
for (let mask = 1; mask < 8; mask++) {
    const on = PACKS.filter((_, i) => mask & (1 << i));
    const grezzo = {};
    for (const id of ids) if (on.includes(packOf(id))) {
        grezzo[OF[id]] = (grezzo[OF[id]] || 0) + 1;
    }
    const prima = ORDER.filter(t => grezzo[t]).length;
    const conta = fold(Object.assign({}, grezzo));
    const vive = ORDER.filter(t => conta[t]);
    const scarse = vive.filter(t => conta[t] < MIN);
    if (scarse.length) problemi++;
    const piegate = prima - vive.length;
    console.log('  ' + on.join('+').padEnd(22) +
        String(vive.length).padStart(2) + ' schede' +
        (piegate ? ' (' + piegate + ' piegate)' : '            ') +
        '  ' + vive.map(t => LABEL[t] + ' ' + conta[t]).join(', ') +
        (scarse.length ? '   <-- ancora magre: ' +
            scarse.map(t => LABEL[t] + '(' + conta[t] + ')').join(', ') : ''));
}

// --- la trappola del pannello del gioco ---------------------------------
// ISWorldMapSymbols dispone su otto colonne e poi fa joypadButtonsY[floor(n/2)]:
// una scheda che sta su una riga sola (otto tessere o meno) gli fa fare #nil, e
// aprire la mappa crasha. Il pannello lo nascondiamo, ma il gioco lo costruisce
// lo stesso, quindi le schede dichiarate a MapSymbolDefinitions devono essere
// tutte piene. Noi dichiariamo solo le tre del gioco: qui si verifica.
const VT = {};
for (const m of (src.split('C.VANILLA_TAB[')[0], src).matchAll(/C\.VANILLA_TAB\[(\w)\]\s*=\s*"([^"]+)"/g)) {
    VT[abbrev[m[1]]] = m[2];
}
const COLONNE = 8;
console.log('\nschede dichiarate al gioco (ognuna deve superare le ' + COLONNE +
    ' tessere, o il gioco crasha):');
let trappola = 0;
// Due scenari: con i 95 registrati da noi, e senza - quando Add More Map
// Symbols e' gia' installato e ce li mette lui, sotto le sue schede.
for (const [nome, registrati] of [
    ['da soli        ', ids.filter(id => packOf(id) !== 'vanilla')],
    ['con AMMS acceso', ids.filter(id => packOf(id) === 'extra')],
]) {
    const perScheda = {};
    for (const id of registrati) {
        const t = VT[OF[id]] || 'Symbols';
        perScheda[t] = (perScheda[t] || 0) + 1;
    }
    const male = Object.entries(perScheda).filter(([, n]) => n <= COLONNE);
    if (male.length) { trappola++; problemi++; }
    console.log('  ' + nome + '  ' +
        Object.entries(perScheda).map(([t, n]) => t + ' ' + n).join(', ') +
        (male.length ? '   <-- una riga sola: ' + male.map(([t]) => t).join(', ') : ''));
}
if (!trappola) console.log('  nessuna scheda a riga singola in nessuno dei due casi.');

console.log(problemi
    ? `\n${problemi} combinazioni con almeno una scheda sotto le 3 tessere.`
    : '\nnessuna scheda scende sotto le 3 tessere, in nessuna combinazione.');
