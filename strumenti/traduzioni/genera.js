/*  genera.js - scrive media/lua/shared/Translate/<LINGUA>/ per tutte e 26.

    Sorgenti:
      lingue.js          l'ordine delle colonne
      voc-interfaccia.js le stringhe dell'interfaccia, gia' chiave per chiave
      voc-simboli-*.js   i concetti, una riga per concetto
      mappa-simboli.js   quale simbolo usa quale concetto

    Per ogni lingua escono quattro file, come nelle altre mod di casa:
      IG_UI.json / IG_UI_<L>.txt   le chiavi IGUI_*
      UI.json    / UI_<L>.txt      le chiavi UI_*
      Sandbox.json / Sandbox_<L>.txt le chiavi Sandbox_* (media/sandbox-options.txt)
    I .txt sono la rete per le build vecchie: a 42.20 il gioco legge i json, ma
    le due copie devono avere le stesse chiavi.

    Uso:  node MOD/ProjectWriting/strumenti/traduzioni/genera.js
*/
const fs = require('fs');
const path = require('path');

const LANGS = require('./lingue.js');
const UI = require('./voc-interfaccia.js');
const MAP = require('./mappa-simboli.js');
const WORDS = Object.assign({},
    require('./voc-simboli-1.js'),
    require('./voc-simboli-2.js'),
    require('./voc-simboli-3.js'));

const OUT = path.join(__dirname, '..', '..', 'workshop', 'Contents', 'mods',
    'ProjectWriting', '42.20', 'media', 'lua', 'shared', 'Translate');

// --- controlli, prima di scrivere qualsiasi cosa -------------------------
let problemi = 0;
const lamenta = m => { console.error('  ' + m); problemi++; };

for (const [key, row] of Object.entries(UI)) {
    if (row.length !== LANGS.length) {
        lamenta(`${key}: ${row.length} colonne invece di ${LANGS.length}`);
    }
    row.forEach((v, i) => { if (!v) lamenta(`${key}: ${LANGS[i]} vuoto`); });
}
for (const [slug, row] of Object.entries(WORDS)) {
    if (row.length !== LANGS.length) {
        lamenta(`concetto ${slug}: ${row.length} colonne invece di ${LANGS.length}`);
    }
    row.forEach((v, i) => { if (!v) lamenta(`concetto ${slug}: ${LANGS[i]} vuoto`); });
}
for (const [id, slug] of Object.entries(MAP)) {
    if (!WORDS[slug]) lamenta(`${id} punta al concetto "${slug}", che non esiste`);
}
const usati = new Set(Object.values(MAP));
for (const slug of Object.keys(WORDS)) {
    if (!usati.has(slug)) lamenta(`concetto "${slug}" non usato da nessun simbolo`);
}
if (problemi) {
    console.error(`\n${problemi} problemi: non ho scritto niente.`);
    process.exit(1);
}

// --- e quello che c'e' gia' sul disco, che questo file sta per coprire ----
//
// I json si scrivono da zero: quello che non sta nel vocabolario non esce, e
// una chiave aggiunta a mano dentro un json sopravvive solo fino alla prima
// rigenerazione. E' successo davvero - trenta chiavi sparite in silenzio da 52
// file per aggiungerne una (lezione 61) - e nessun controllo se n'era accorto,
// perche' sparire da tutte e 26 le lingue insieme le lascia allineate.
//
// Qui si guarda cosa c'e' gia' in EN prima di toccarlo: se una chiave che il
// gioco leggeva non ha piu' una riga nel vocabolario, non si scrive niente.
{
    const nuove = new Set(Object.keys(stringhe(0)));
    for (const f of ['IG_UI.json', 'UI.json', 'Sandbox.json']) {
        const vecchio = path.join(OUT, 'EN', f);
        if (!fs.existsSync(vecchio)) continue;
        let prima;
        try { prima = JSON.parse(fs.readFileSync(vecchio, 'utf8')); } catch (e) { continue; }
        const perse = Object.keys(prima).filter(k => !nuove.has(k));
        if (perse.length) {
            console.error('');
            console.error(perse.length + ' chiavi sono in ' + f + ' e non nel vocabolario:');
            perse.forEach(k => console.error('  ' + k + ' = ' + JSON.stringify(prima[k])));
            console.error('');
            console.error('Riscrivendo le cancellerei. Mettile in voc-interfaccia.js - le 26');
            console.error('traduzioni sono nei json di ogni lingua - e rilancia.');
            console.error('Se vanno tolte davvero, cancellale a mano dai json e rilancia.');
            process.exit(1);
        }
    }
}

// --- costruzione ---------------------------------------------------------
/** Tutte le chiavi di una lingua, IGUI_* e UI_* insieme. */
function stringhe(langIndex) {
    const out = {};
    for (const [key, row] of Object.entries(UI)) out[key] = row[langIndex];
    for (const [id, slug] of Object.entries(MAP)) {
        out['IGUI_NW_Sym_' + id] = WORDS[slug][langIndex];
    }
    return out;
}

const escapeJson = s => JSON.stringify(s);

/** Il vecchio formato .txt: IG_UI_IT = { chiave = "valore", ... }, come le altre mod. */
function comeTxt(prefisso, lang, righe) {
    const corpo = Object.entries(righe)
        .map(([k, v]) => `\t${k} = ${escapeJson(v)},`)
        .join('\n');
    return `${prefisso}_${lang} = {\n${corpo}\n}\n`;
}

function comeJson(righe) {
    const corpo = Object.entries(righe)
        .map(([k, v]) => `    ${escapeJson(k)}: ${escapeJson(v)}`)
        .join(',\n');
    return `{\n${corpo}\n}\n`;
}

let chiaviIG = 0, chiaviUI = 0, chiaviSB = 0;
LANGS.forEach((lang, i) => {
    const tutte = stringhe(i);
    const ig = {}, ui = {}, sb = {};
    for (const [k, v] of Object.entries(tutte)) {
        if (k.startsWith('IGUI_')) ig[k] = v;
        else if (k.startsWith('Sandbox_')) sb[k] = v;
        else ui[k] = v;
    }
    chiaviIG = Object.keys(ig).length;
    chiaviUI = Object.keys(ui).length;
    chiaviSB = Object.keys(sb).length;

    const dir = path.join(OUT, lang);
    fs.mkdirSync(dir, { recursive: true });
    // UTF-8 senza BOM: e' quello che il gioco si aspetta e quello che spedisce
    // il resto della famiglia.
    fs.writeFileSync(path.join(dir, 'IG_UI.json'), comeJson(ig), 'utf8');
    fs.writeFileSync(path.join(dir, `IG_UI_${lang}.txt`), comeTxt('IG_UI', lang, ig), 'utf8');
    fs.writeFileSync(path.join(dir, 'UI.json'), comeJson(ui), 'utf8');
    fs.writeFileSync(path.join(dir, `UI_${lang}.txt`), comeTxt('UI', lang, ui), 'utf8');
    // Le opzioni sandbox: il nome della pagina e di ogni opzione, e il tooltip.
    // Il gioco le cerca da se' in Sandbox.json, per nome (Sandbox_<translation>).
    if (chiaviSB) {
        fs.writeFileSync(path.join(dir, 'Sandbox.json'), comeJson(sb), 'utf8');
        fs.writeFileSync(path.join(dir, `Sandbox_${lang}.txt`), comeTxt('Sandbox', lang, sb), 'utf8');
    }
});

console.log(`${LANGS.length} lingue scritte in ${path.relative(process.cwd(), OUT)}`);
console.log(`  ${chiaviIG} chiavi IGUI_ (di cui ${Object.keys(MAP).length} nomi di simboli)`);
console.log(`  ${chiaviUI} chiavi UI_`);
console.log(`  ${chiaviSB} chiavi Sandbox_`);
