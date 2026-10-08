/*  scrivibili.js - quali oggetti scrivibili di vanilla abbiamo, e quali no.

    Vanilla dichiara `CanBeWrite = true` su un certo numero di voci di
    `scripts/generated/items/literature.txt`, e il menu contestuale offre
    "Scrivi qualcosa" esattamente su quelle. La nostra finestra si apre solo per
    gli oggetti che stanno in `L.BY_ITEM`; per gli altri si torna a vanilla, che
    e' un ripiego voluto ma silenzioso.

    Silenzioso e' il problema: un oggetto dimenticato non da' nessun segnale -
    si apre la finestra del gioco e sembra che la mod non ci sia. Questo elenco
    lo dice prima di aprire il gioco.

    Controlla anche che ogni supporto nominato in BY_ITEM esista davvero in
    L.MEDIA: e' la svista che ha tenuto fuori i biglietti per un giro intero.

    Uso:  node MOD/ProjectWriting/strumenti/controlli/scrivibili.js
*/
const fs = require('fs'), path = require('path');

const GIOCO = 'C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/media';
const LUA = path.join(__dirname, '..', '..', 'workshop', 'Contents', 'mods',
    'ProjectWriting', '42.20', 'media', 'lua', 'shared', 'NeatWriting',
    'NW_Layouts.lua');

// --- gli scrivibili di vanilla -------------------------------------------
const lit = path.join(GIOCO, 'scripts/generated/items/literature.txt');
if (!fs.existsSync(lit)) {
    console.log('non trovo literature.txt: il gioco non e\' dove me lo aspetto');
    process.exit(1);
}
const testo = fs.readFileSync(lit, 'utf8');
const scrivibili = [];
{
    let nome = null;
    for (const riga of testo.split('\n')) {
        const m = riga.match(/^\s*item\s+(\w+)/);
        if (m) { nome = m[1]; continue; }
        if (/CanBeWrite\s*=\s*true/i.test(riga) && nome) scrivibili.push(nome);
    }
}

// --- la nostra tabella ----------------------------------------------------
const src = fs.readFileSync(LUA, 'utf8');

const mediaKeys = new Set(
    [...src.matchAll(/^\s{4}(\w+)\s*=\s*\{\s*$/gm)].map(m => m[1]));

const byItem = {};
{
    const blocco = src.match(/L\.BY_ITEM = \{([\s\S]*?)\n\}/);
    if (blocco) {
        for (const m of blocco[1].matchAll(/^\s*(\w+)\s*=\s*"(\w+)"/gm)) byItem[m[1]] = m[2];
    }
}

// --- il verdetto ----------------------------------------------------------
const coperti = scrivibili.filter(i => byItem[i]);
const scoperti = scrivibili.filter(i => !byItem[i]);
const orfani = Object.entries(byItem).filter(([, v]) => !mediaKeys.has(v));
const extra = Object.keys(byItem).filter(i => !scrivibili.includes(i));

console.log('vanilla dichiara ' + scrivibili.length + ' oggetti scrivibili.');
console.log('noi ne copriamo ' + coperti.length + '.\n');

if (scoperti.length) {
    console.log('SCOPERTI (aprono la finestra di vanilla):');
    for (const i of scoperti) console.log('  ' + i);
    console.log();
}

if (orfani.length) {
    console.log('SUPPORTI CHE NON ESISTONO (L.MEDIA non ha quella chiave):');
    for (const [i, v] of orfani) console.log('  ' + i + ' -> "' + v + '"');
    console.log();
}

if (extra.length) {
    console.log('NOSTRI E NON DI VANILLA (mod, o nomi cambiati in una build):');
    for (const i of extra) console.log('  ' + i);
    console.log();
}

if (!scoperti.length && !orfani.length) {
    console.log('tutti coperti, e ogni supporto nominato esiste.');
}
process.exit(orfani.length ? 1 : 0);
