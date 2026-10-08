/*  genera-maniglia-sinistra.js - la maniglia d'angolo, per l'angolo opposto.
 *
 *  Il pannello Writing sulla mappa del mondo sta nell'angolo destro
 *  dell'interfaccia e cresce verso sinistra, quindi la sua maniglia sta in
 *  basso a sinistra - e la freccia deve puntare da quella parte, o dice il
 *  contrario di quello che fa.
 *
 *  PERCHE' UN FILE E NON UNO SPECCHIO A RUNTIME. Il primo tentativo ribaltava
 *  la texture con drawTextureAllPoint, scambiando i due angoli di sinistra con
 *  quelli di destra. Non si vedeva niente: specchiare inverte il verso di
 *  avvolgimento del quadrilatero, e un quadrilatero al contrario il motore lo
 *  scarta. Da fuori sembrava una maniglia "scollegata dal pannello", che era
 *  poi il modo giusto di descrivere una maniglia che non c'era.
 *
 *  Specchiare i pixel una volta sola, qui, costa 1,8 KB nel pacchetto e toglie
 *  di mezzo il problema: in gioco resta un drawTextureScaled come tutti gli
 *  altri.
 *
 *      node MOD/ProjectWriting/strumenti/arte/genera-maniglia-sinistra.js
 */
const path = require('path');
const { readPNG, writePNG } = require('../controlli/png.js');

const UI = path.join(__dirname, '..', '..', 'workshop', 'Contents', 'mods',
    'ProjectWriting', '42.20', 'media', 'ui', 'NeatWriting');

const src = readPNG(path.join(UI, 'ResizeGrip.png'));
const out = Buffer.alloc(src.rgba.length);

for (let y = 0; y < src.h; y++) {
    for (let x = 0; x < src.w; x++) {
        const from = (y * src.w + (src.w - 1 - x)) * 4;   // stessa riga, colonna specchiata
        const to = (y * src.w + x) * 4;
        src.rgba.copy(out, to, from, from + 4);
    }
}

const dest = path.join(UI, 'ResizeGripLeft.png');
writePNG(dest, src.w, src.h, out);
console.log('ResizeGripLeft.png scritta, ' + src.w + 'x' + src.h);
