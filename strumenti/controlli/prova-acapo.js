/*  prova-acapo.js - il banco di prova dell'a capo automatico.

    NW_Writer.layout e' l'unico pezzo di questa mod che gira su ogni battuta e
    che, se sbaglia, sbaglia in silenzio: perde un pezzo di frase, mette il
    cursore su una riga che non esiste, o - nel caso peggiore - non finisce mai
    e pianta la finestra. In gioco non si prova; qui si'.

    L'algoritmo e' ricopiato riga per riga dal Lua, con una misura finta ma
    coerente al posto di MeasureStringX. Si controllano tre cose:

      1. che termini sempre (c'e' un contatore di sicurezza);
      2. che non perda caratteri per strada;
      3. che gli scarti from/to puntino davvero a quel pezzo di testo - sono
         quelli che fanno funzionare il cursore e la gomma riga per riga.

    Uso:  node MOD/ProjectWriting/strumenti/controlli/prova-acapo.js
          esce con 1 se una prova fallisce, cosi si puo mettere in coda ai
          controlli statici.
*/

// una misura finta ma coerente: ogni carattere vale la sua larghezza
const W = { i: 3, l: 3, m: 14, ' ': 5 };
const adv = c => W[c] !== undefined ? W[c] : 8;
const measure = s => [...s].reduce((n, c) => n + adv(c), 0);

function layout(text, width) {
    const out = [];
    if (!text) return out;
    const len = text.length;
    let from = 1, i = 1, lastSpace = null;
    let guard = 0;
    while (i <= len) {
        if (++guard > 200000) throw new Error('CICLO INFINITO');
        const ch = text[i - 1];
        if (ch === '\n') {
            out.push({ text: text.slice(from - 1, i - 1), from, to: i - 1 });
            i++; from = i; lastSpace = null;
        } else if (i > from && measure(text.slice(from - 1, i)) > width) {
            if (lastSpace && lastSpace > from) {
                out.push({ text: text.slice(from - 1, lastSpace - 1), from, to: lastSpace - 1 });
                from = lastSpace + 1; i = from;
            } else {
                out.push({ text: text.slice(from - 1, i - 1), from, to: i - 1 });
                from = i;
            }
            lastSpace = null;
        } else {
            if (ch === ' ') lastSpace = i;
            i++;
        }
    }
    out.push({ text: text.slice(from - 1, len), from, to: len });
    return out;
}

let fail = 0;
function check(name, text, width) {
    let lines;
    try { lines = layout(text, width); }
    catch (e) { console.log('FALLITO  ' + name + ': ' + e.message); fail++; return; }

    // 1. nessuna riga piu' larga della colonna (salvo una parola indivisibile)
    for (const l of lines) {
        if (l.text.length > 1 && measure(l.text) > width) {
            console.log(`FALLITO  ${name}: riga larga ${measure(l.text)} > ${width}: "${l.text}"`);
            fail++; return;
        }
    }
    // 2. gli scarti devono ricomporre il testo, spazi e a capo mangiati a parte
    const joined = lines.map(l => l.text).join('');
    const stripped = text.replace(/[\n ]/g, '');
    if (joined.replace(/[\n ]/g, '') !== stripped) {
        console.log(`FALLITO  ${name}: caratteri persi (${joined.length} vs ${text.length})`);
        fail++; return;
    }
    // 3. gli indici devono puntare al testo vero
    for (const l of lines) {
        if (text.slice(l.from - 1, l.to) !== l.text) {
            console.log(`FALLITO  ${name}: scarto sbagliato su "${l.text}"`);
            fail++; return;
        }
    }
    console.log(`ok       ${name.padEnd(34)} ${lines.length} righe`);
}

check('vuoto', '', 100);
check('una parola', 'ciao', 100);
check('frase che va a capo', 'nel mezzo del cammin di nostra vita mi ritrovai per una selva oscura', 100);
check('a capo a mano', 'prima riga\nseconda riga\n\nquarta', 100);
check('parola piu larga della riga', 'mmmmmmmmmmmmmmmmmmmmmmmm parola', 40);
check('colonna strettissima', 'abcdefgh ijkl', 5);
check('solo spazi', '        ', 40);
check('spazi in coda', 'parola   ', 40);
check('a capo finale', 'riga\n', 100);
check('molti a capo', '\n\n\n\n', 100);
check('testo lungo', 'lorem ipsum dolor sit amet '.repeat(60), 220);
check('senza spazi lungo', 'x'.repeat(500), 60);

console.log();
console.log(fail === 0 ? 'tutte le prove passate.' : fail + ' prove fallite.');
process.exit(fail === 0 ? 0 : 1);
