#!/usr/bin/env node
// Génère assets/brand/mark-glyphes.png à partir du monogramme officiel (assets/brand/mark-paper.png).
//
// Le monogramme FS est un losange arrondi plein, dont les lettres « fs » sont des JOURS (pixels transparents).
// Le bouton « Continuer avec FS Connect » pose les lettres seules, claires, sur un petit carré sombre (comme le
// « FS » du bouton du SaaS) : il faut donc l'inverse, les lettres pleines et tout le reste transparent.
//
// Méthode : on remplit depuis les bords tout ce qui est transparent (l'extérieur du losange) ; ce qui reste
// transparent est à l'intérieur, donc une lettre. Alpha d'une lettre = 255 − alpha du losange (bords lissés
// conservés). Couleur blanche : le widget la teinte (BlendMode.srcIn). Recadrage carré autour des lettres.
//
// Usage (Node 18+, aucune dépendance) : node tool/generer-glyphes-monogramme.cjs
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const racine = path.resolve(__dirname, '..');
const source = path.join(racine, 'assets/brand/mark-paper.png');
const cible = path.join(racine, 'assets/brand/mark-glyphes.png');

function lirePng(fichier) {
  const b = fs.readFileSync(fichier);
  let o = 8, w = 0, h = 0, type = 0, prof = 0;
  const idat = [];
  while (o < b.length) {
    const l = b.readUInt32BE(o), t = b.toString('ascii', o + 4, o + 8), d = b.subarray(o + 8, o + 8 + l);
    if (t === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); prof = d[8]; type = d[9]; }
    if (t === 'IDAT') idat.push(d);
    o += 12 + l;
  }
  if (prof !== 8 || type !== 6) throw new Error('PNG RGBA 8 bits attendu');
  const brut = zlib.inflateSync(Buffer.concat(idat));
  const bpp = 4, pas = w * bpp, px = Buffer.alloc(h * pas);
  for (let y = 0; y < h; y++) {
    const f = brut[y * (pas + 1)];
    for (let x = 0; x < pas; x++) {
      const a = x >= bpp ? px[y * pas + x - bpp] : 0;
      const u = y ? px[(y - 1) * pas + x] : 0;
      const c = y && x >= bpp ? px[(y - 1) * pas + x - bpp] : 0;
      let v = brut[y * (pas + 1) + 1 + x];
      if (f === 1) v += a;
      else if (f === 2) v += u;
      else if (f === 3) v += (a + u) >> 1;
      else if (f === 4) {
        const p = a + u - c, pa = Math.abs(p - a), pb = Math.abs(p - u), pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? u : c;
      }
      px[y * pas + x] = v & 255;
    }
  }
  return { w, h, px };
}

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buf) {
  let c = 0xffffffff;
  for (const x of buf) c = crcTable[(c ^ x) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function bloc(type, data) {
  const l = Buffer.alloc(4); l.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td));
  return Buffer.concat([l, td, c]);
}
function ecrirePng(fichier, w, h, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  const lignes = Buffer.alloc(h * (w * 4 + 1));
  for (let y = 0; y < h; y++) rgba.copy(lignes, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  fs.writeFileSync(fichier, Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    bloc('IHDR', ihdr), bloc('IDAT', zlib.deflateSync(lignes, { level: 9 })), bloc('IEND', Buffer.alloc(0)),
  ]));
}

const { w, h, px } = lirePng(source);
const alpha = (x, y) => px[(y * w + x) * 4 + 3];

// 1. Extérieur : transparent (< 128) et relié aux bords.
const dehors = new Uint8Array(w * h);
const pile = [];
for (let x = 0; x < w; x++) { pile.push([x, 0], [x, h - 1]); }
for (let y = 0; y < h; y++) { pile.push([0, y], [w - 1, y]); }
while (pile.length) {
  const [x, y] = pile.pop();
  if (x < 0 || y < 0 || x >= w || y >= h) continue;
  const i = y * w + x;
  if (dehors[i] || alpha(x, y) >= 128) continue;
  dehors[i] = 1;
  pile.push([x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]);
}
// 2. Dilatation de 2 px : le liseré lissé du contour extérieur n'est pas une lettre.
let zone = dehors;
for (let passe = 0; passe < 2; passe++) {
  const z = Uint8Array.from(zone);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (zone[y * w + x]) continue;
    if ((x > 0 && zone[y * w + x - 1]) || (x < w - 1 && zone[y * w + x + 1]) ||
        (y > 0 && zone[(y - 1) * w + x]) || (y < h - 1 && zone[(y + 1) * w + x])) z[y * w + x] = 1;
  }
  zone = z;
}
// 3. Lettres = intérieur, alpha inversé ; boîte englobante.
const sortie = Buffer.alloc(w * h * 4);
let x0 = w, y0 = h, x1 = -1, y1 = -1;
for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
  const i = y * w + x;
  const a = zone[i] ? 0 : 255 - alpha(x, y);
  if (a > 8) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
  sortie[i * 4] = 255; sortie[i * 4 + 1] = 255; sortie[i * 4 + 2] = 255; sortie[i * 4 + 3] = a;
}
if (x1 < 0) throw new Error('aucune lettre trouvée');
// 4. Recadrage carré centré sur les lettres, 4 % de marge.
const cote = Math.ceil(Math.max(x1 - x0 + 1, y1 - y0 + 1) * 1.04);
const cx = (x0 + x1 + 1) / 2, cy = (y0 + y1 + 1) / 2;
const ox = Math.round(cx - cote / 2), oy = Math.round(cy - cote / 2);
const carre = Buffer.alloc(cote * cote * 4);
for (let y = 0; y < cote; y++) for (let x = 0; x < cote; x++) {
  const sx = ox + x, sy = oy + y;
  if (sx < 0 || sy < 0 || sx >= w || sy >= h) continue;
  sortie.copy(carre, (y * cote + x) * 4, (sy * w + sx) * 4, (sy * w + sx) * 4 + 4);
}
ecrirePng(cible, cote, cote, carre);
console.log(`mark-glyphes.png : ${cote}×${cote} px (lettres ${x1 - x0 + 1}×${y1 - y0 + 1} px dans un monogramme de ${w}×${h})`);
