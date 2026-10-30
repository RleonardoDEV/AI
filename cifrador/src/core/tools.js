// Herramientas: contraseñas, codificaciones, cifrados clásicos y esteganografía.
import { utf8, fromUtf8, b64u, fromB64u, hex, fromHex } from './encoding.js';

// --- Generador de contraseñas (sin sesgo: muestreo por rechazo) ---
const SETS = {
  lower: 'abcdefghijkmnopqrstuvwxyz',
  upper: 'ABCDEFGHJKLMNPQRSTUVWXYZ',
  digits: '23456789',
  symbols: '!@#$%&*+-=?_.:;~^',
};

function randomIndex(n) {
  const limit = Math.floor(0x100000000 / n) * n;
  const buf = new Uint32Array(1);
  do crypto.getRandomValues(buf); while (buf[0] >= limit);
  return buf[0] % n;
}

export function generatePassword(length, opts) {
  const pools = Object.keys(SETS).filter((k) => opts[k]).map((k) => SETS[k]);
  if (!pools.length) throw new Error('Elige al menos un tipo de carácter');
  const all = pools.join('');
  const chars = pools.map((p) => p[randomIndex(p.length)]); // uno de cada tipo
  while (chars.length < length) chars.push(all[randomIndex(all.length)]);
  for (let i = chars.length - 1; i > 0; i--) { const j = randomIndex(i + 1); [chars[i], chars[j]] = [chars[j], chars[i]]; }
  return { password: chars.join(''), bits: Math.round(length * Math.log2(all.length)) };
}

/** Estimación aproximada de la fuerza de una contraseña escrita por una persona. */
export function estimateStrength(pw) {
  if (!pw) return { bits: 0, label: '—' };
  let pool = 0;
  if (/[a-z]/.test(pw)) pool += 26;
  if (/[A-Z]/.test(pw)) pool += 26;
  if (/\d/.test(pw)) pool += 10;
  if (/[^a-zA-Z0-9]/.test(pw)) pool += 33;
  let bits = pw.length * Math.log2(pool || 1);
  if (/(.)\1{2,}/.test(pw)) bits *= 0.7;
  if (/^(123|abc|qwe|password|contraseña|admin)/i.test(pw)) bits *= 0.4;
  bits = Math.round(bits);
  const label = bits < 40 ? 'Muy débil' : bits < 60 ? 'Débil' : bits < 80 ? 'Aceptable' : bits < 110 ? 'Fuerte' : 'Muy fuerte';
  return { bits, label };
}

// --- Codificaciones (NO son cifrado: cualquiera las revierte) ---
export const ENCODINGS = {
  'Base64': { enc: (s) => btoa(String.fromCharCode(...utf8(s))), dec: (s) => fromUtf8(Uint8Array.from(atob(s.trim()), (c) => c.charCodeAt(0))) },
  'Base64URL': { enc: (s) => b64u(utf8(s)), dec: (s) => fromUtf8(fromB64u(s)) },
  'Hexadecimal': { enc: (s) => hex(utf8(s)), dec: (s) => fromUtf8(fromHex(s)) },
  'URL (%xx)': { enc: encodeURIComponent, dec: decodeURIComponent },
  'Binario': {
    enc: (s) => Array.from(utf8(s), (b) => b.toString(2).padStart(8, '0')).join(' '),
    dec: (s) => fromUtf8(Uint8Array.from(s.trim().split(/\s+/), (b) => parseInt(b, 2))),
  },
};

// --- Cifrados clásicos (históricos, solo educativos: se rompen en segundos) ---
const shiftChar = (c, k) => {
  const code = c.charCodeAt(0);
  if (code >= 65 && code <= 90) return String.fromCharCode(((code - 65 + k) % 26 + 26) % 26 + 65);
  if (code >= 97 && code <= 122) return String.fromCharCode(((code - 97 + k) % 26 + 26) % 26 + 97);
  return c;
};

export const CLASSICAL = {
  'César': (t, key, dec) => { const k = parseInt(key, 10) || 3; return [...t].map((c) => shiftChar(c, dec ? -k : k)).join(''); },
  'ROT13': (t) => [...t].map((c) => shiftChar(c, 13)).join(''),
  'Atbash': (t) => [...t].map((c) => {
    if (/[a-z]/.test(c)) return String.fromCharCode(219 - c.charCodeAt(0));
    if (/[A-Z]/.test(c)) return String.fromCharCode(155 - c.charCodeAt(0));
    return c;
  }).join(''),
  'Vigenère': (t, key, dec) => {
    const k = (key || '').toLowerCase().replace(/[^a-z]/g, '');
    if (!k) throw new Error('Vigenère necesita una palabra clave (solo letras)');
    let i = 0;
    return [...t].map((c) => {
      if (!/[a-zA-Z]/.test(c)) return c;
      const s = k.charCodeAt(i++ % k.length) - 97;
      return shiftChar(c, dec ? -s : s);
    }).join('');
  },
};

// --- Esteganografía con caracteres invisibles ---
// Esconde un texto (idealmente ya cifrado) dentro de otro texto normal usando
// caracteres de ancho cero. Se ve igual, pero lleva el mensaje dentro.
const ZW = ['​', '‌', '‍', '⁠']; // 2 bits por carácter
const ZW_RE = /[​‌‍⁠]/g;

export function hideInText(cover, secret) {
  if (!cover.trim()) throw new Error('Escribe un texto visible donde esconder el mensaje');
  const bytes = utf8(secret);
  let hidden = '';
  for (const b of bytes) for (let s = 6; s >= 0; s -= 2) hidden += ZW[(b >> s) & 3];
  const cut = cover.indexOf(' ') > 0 ? cover.indexOf(' ') : Math.min(1, cover.length);
  return cover.slice(0, cut) + '﻿' + hidden + '﻿' + cover.slice(cut);
}

export function revealFromText(text) {
  const m = /﻿([​‌‍⁠]+)﻿/.exec(text);
  if (!m) throw new Error('No se ha encontrado ningún mensaje oculto');
  const chars = [...m[1]];
  const out = new Uint8Array(chars.length / 4);
  for (let i = 0; i < out.length; i++) {
    let b = 0;
    for (let j = 0; j < 4; j++) b = (b << 2) | ZW.indexOf(chars[i * 4 + j]);
    out[i] = b;
  }
  return fromUtf8(out);
}

export const stripHidden = (t) => t.replace(ZW_RE, '').replace(/﻿/g, '');
