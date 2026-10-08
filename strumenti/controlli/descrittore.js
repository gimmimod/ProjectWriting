/*  descrittore.js - legge NW_Layouts.lua e ne restituisce i supporti.

    Gli strumenti qui dentro devono lavorare sugli stessi numeri della mod, non
    su una copia: se il descrittore cambia, il conto deve cambiare con lui. Per
    un po' ognuno se lo leggeva da se' con una espressione regolare che pretendeva
    i campi in un ordine preciso, ed e' bastato aggiungere `marginY` per far
    tornare zero voci a tutti e due - senza errore, solo tabelle vuote.

    Qui si taglia il file in blocchi `{ id = "..." ... }` e si pescano i campi
    per nome, uno per uno. Un campo nuovo non rompe niente; un campo che sparisce
    torna undefined e si vede.

    Uso:  const { leggi } = require('./descrittore');
          for (const md of leggi()) ...
*/
const fs = require('fs'), path = require('path');

const FILE = path.join(__dirname, '..', '..', 'workshop', 'Contents', 'mods',
    'ProjectWriting', '42.20', 'media', 'lua', 'shared', 'NeatWriting',
    'NW_Layouts.lua');

/** Un numero per nome dentro un pezzo di Lua, o undefined. */
function num(src, name) {
    const m = src.match(new RegExp('\\b' + name + '\\s*=\\s*([\\d.]+)'));
    return m ? +m[1] : undefined;
}

/** Il blocco `text = { ... }` di un supporto. */
function testo(src) {
    const m = src.match(/text\s*=\s*\{([^}]*)\}/);
    return m ? m[1] : '';
}

/** I supporti, nell'ordine in cui stanno nel file. */
function leggi() {
    const LUA = fs.readFileSync(FILE, 'utf8');
    const out = [];
    // Ogni voce comincia con il suo id; il blocco arriva fino al successivo.
    // Si cattura anche la CHIAVE con cui la voce e' intestata: L.MEDIA e' una
    // tabella a chiavi, e una voce scritta come elemento di array finisce in
    // L.MEDIA[1] invece che in L.MEDIA["card"]. La mod la ignora, questo
    // lettore invece la vedeva lo stesso - e le tabelle dicevano che il
    // supporto c'era mentre in gioco non esisteva.
    const teste = [...LUA.matchAll(/(?:(\w+)\s*=\s*)?\{\s*id = "(\w+)", texture = TEX \.\. "([^"]+)"/g)];
    for (let i = 0; i < teste.length; i++) {
        const from = teste[i].index;
        const to = i + 1 < teste.length ? teste[i + 1].index : LUA.length;
        const src = LUA.slice(from, to);
        const t = testo(src);
        const areas = [...(src.match(/areas = \{[^\n]+/) || [''])[0]
            .matchAll(/\{ (\d+), (\d+), (\d+), (\d+) \}/g)]
            .map(a => a.slice(1).map(Number));
        out.push({
            chiave: teste[i][1] || null,
            id: teste[i][2],
            texture: teste[i][3],
            w: num(src, 'width'), h: num(src, 'height'),
            sheets: num(src, 'sheets'),
            areas,
            line: num(t, 'line'),
            margin: num(t, 'margin'),
            marginY: num(t, 'marginY') !== undefined ? num(t, 'marginY') : num(t, 'margin'),
            first: num(t, 'first') !== undefined ? num(t, 'first') : null,
            ruled: /ruled\s*=\s*true/.test(t),
            pages: num(src, 'pages'),
        });
    }
    return out;
}

/** Grida se il descrittore e' cambiato di forma sotto i piedi. */
function controlla(media, attesi = 9) {
    const guai = [];
    if (media.length !== attesi)
        guai.push(`lette ${media.length} voci su ${attesi}: il descrittore e' cambiato di forma`);
    for (const md of media) {
        if (md.chiave !== md.id) {
            guai.push(md.id + ": la voce e' intestata "
                + (md.chiave ? '"' + md.chiave + '"' : 'da niente (elemento di array)')
                + " invece che \"" + md.id + "\" - in gioco L.MEDIA[\"" + md.id + "\"] e' nil");
        }
        for (const c of ['w', 'h', 'sheets', 'line', 'margin', 'marginY', 'pages'])
            if (md[c] === undefined) guai.push(`${md.id}: manca ${c}`);
        if (!md.areas.length) guai.push(`${md.id}: nessuna area`);
        else if (md.areas.length !== md.sheets)
            guai.push(`${md.id}: ${md.areas.length} aree per ${md.sheets} facciate`);
    }
    if (guai.length) console.log('ATTENZIONE\n  ' + guai.join('\n  ') + '\n');
    return guai;
}

module.exports = { leggi, controlla, FILE };
