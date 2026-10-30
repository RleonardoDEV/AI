// Cifrado con contraseña. Formato de texto autodescriptivo:
//   cifra1.<alg>.<parámetros>.<sal>.<nonce>.<cifrado>
// Los cinco primeros campos forman la "cabecera", que se autentica como
// datos asociados (AAD): si alguien la altera, el descifrado falla.
import { getSodium } from './sodium.js';
import { utf8, fromUtf8, b64u, fromB64u, concat, randomBytes } from './encoding.js';

export const ALGORITHMS = {
  xc: {
    name: 'XChaCha20-Poly1305 + Argon2id',
    note: 'Recomendado. Moderno, rápido en móviles y resistente a ataques con tarjetas gráficas.',
  },
  ag: {
    name: 'AES-256-GCM + PBKDF2-SHA256',
    note: 'Estándar del gobierno de EE. UU. (NIST). Máxima compatibilidad.',
  },
  cc: {
    name: 'Cascada CIFRA (AES-256-GCM + XChaCha20-Poly1305)',
    note: 'Doble capa con claves independientes: sigue segura aunque uno de los dos algoritmos se rompiera.',
  },
};

const ARGON = { ops: 3, memMiB: 64 };
const PBKDF2_ITER = 600000;

async function argon2id(password, salt, len, ops, memMiB) {
  const s = await getSodium();
  return s.crypto_pwhash(len, utf8(password), salt, ops, memMiB * 1024 * 1024, s.crypto_pwhash_ALG_ARGON2ID13);
}

async function pbkdf2Key(password, salt, iter) {
  const base = await crypto.subtle.importKey('raw', utf8(password), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations: iter },
    base, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

async function aesGcm(mode, rawOrKey, iv, data, aad) {
  const key = rawOrKey instanceof Uint8Array
    ? await crypto.subtle.importKey('raw', rawOrKey, 'AES-GCM', false, [mode])
    : rawOrKey;
  const fn = mode === 'encrypt' ? crypto.subtle.encrypt : crypto.subtle.decrypt;
  return new Uint8Array(await fn.call(crypto.subtle, { name: 'AES-GCM', iv, additionalData: aad }, key, data));
}

export async function xchacha(mode, key, nonce, data, aad) {
  const s = await getSodium();
  return mode === 'encrypt'
    ? s.crypto_aead_xchacha20poly1305_ietf_encrypt(data, aad, null, nonce, key)
    : s.crypto_aead_xchacha20poly1305_ietf_decrypt(null, data, aad, nonce, key);
}

/** Cifra bytes con contraseña. Devuelve { header, ciphertext }. */
export async function encryptBytes(password, data, alg = 'xc') {
  if (!password) throw new Error('Escribe una contraseña');
  const salt = randomBytes(16);
  if (alg === 'xc') {
    const nonce = randomBytes(24);
    const header = `cifra1.xc.a${ARGON.ops}m${ARGON.memMiB}.${b64u(salt)}.${b64u(nonce)}`;
    const key = await argon2id(password, salt, 32, ARGON.ops, ARGON.memMiB);
    return { header, ciphertext: await xchacha('encrypt', key, nonce, data, utf8(header)) };
  }
  if (alg === 'ag') {
    const iv = randomBytes(12);
    const header = `cifra1.ag.p${PBKDF2_ITER}.${b64u(salt)}.${b64u(iv)}`;
    const key = await pbkdf2Key(password, salt, PBKDF2_ITER);
    return { header, ciphertext: await aesGcm('encrypt', key, iv, data, utf8(header)) };
  }
  if (alg === 'cc') {
    const iv = randomBytes(12), nonce = randomBytes(24);
    const header = `cifra1.cc.a${ARGON.ops}m${ARGON.memMiB}.${b64u(salt)}.${b64u(concat(iv, nonce))}`;
    const k = await argon2id(password, salt, 64, ARGON.ops, ARGON.memMiB);
    const aad = utf8(header);
    const inner = await aesGcm('encrypt', k.slice(0, 32), iv, data, aad);
    return { header, ciphertext: await xchacha('encrypt', k.slice(32), nonce, inner, aad) };
  }
  throw new Error('Algoritmo desconocido: ' + alg);
}

export async function decryptBytes(password, header, ciphertext) {
  const [magic, alg, params, saltS, nonceS] = header.split('.');
  if (magic !== 'cifra1') throw new Error('No es un mensaje de CIFRA');
  const salt = fromB64u(saltS), nonce = fromB64u(nonceS), aad = utf8(header);
  const fail = () => { throw new Error('Contraseña incorrecta o mensaje alterado'); };
  try {
    if (alg === 'xc' || alg === 'cc') {
      const m = /^a(\d+)m(\d+)$/.exec(params);
      if (!m) fail();
      const ops = +m[1], mem = +m[2];
      if (ops > 20 || mem > 1024) throw new Error('Parámetros sospechosos');
      if (alg === 'xc') {
        const key = await argon2id(password, salt, 32, ops, mem);
        return await xchacha('decrypt', key, nonce, ciphertext, aad);
      }
      const k = await argon2id(password, salt, 64, ops, mem);
      const inner = await xchacha('decrypt', k.slice(32), nonce.slice(12), ciphertext, aad);
      return await aesGcm('decrypt', k.slice(0, 32), nonce.slice(0, 12), inner, aad);
    }
    if (alg === 'ag') {
      const iter = +params.slice(1);
      if (!(iter >= 10000 && iter <= 10000000)) fail();
      const key = await pbkdf2Key(password, salt, iter);
      return await aesGcm('decrypt', key, nonce, ciphertext, aad);
    }
  } catch (e) {
    if (e.message === 'Parámetros sospechosos') throw e;
    fail();
  }
  throw new Error('Algoritmo no compatible con contraseña: ' + alg);
}

export function splitMessage(text) {
  const t = text.trim().replace(/\s+/g, '');
  const parts = t.split('.');
  if (parts.length !== 6 || parts[0] !== 'cifra1') throw new Error('Formato no reconocido. Debe empezar por "cifra1."');
  return { header: parts.slice(0, 5).join('.'), alg: parts[1], ciphertext: fromB64u(parts[5]) };
}

export async function encryptText(password, text, alg) {
  const { header, ciphertext } = await encryptBytes(password, utf8(text), alg);
  return `${header}.${b64u(ciphertext)}`;
}

export async function decryptText(password, message) {
  const { header, ciphertext } = splitMessage(message);
  return fromUtf8(await decryptBytes(password, header, ciphertext));
}

// --- Cifrado con clave aleatoria (para enlaces seguros) ---
export async function encryptWithRandomKey(text) {
  const key = randomBytes(32), nonce = randomBytes(24);
  const header = `cifra1.rk.-.-.${b64u(nonce)}`;
  const ct = await xchacha('encrypt', key, nonce, utf8(text), utf8(header));
  return { key: b64u(key), message: `${header}.${b64u(ct)}` };
}

export async function decryptWithKey(keyB64, message) {
  const { header, ciphertext } = splitMessage(message);
  const nonce = fromB64u(header.split('.')[4]);
  try {
    return fromUtf8(await xchacha('decrypt', fromB64u(keyB64), nonce, ciphertext, utf8(header)));
  } catch { throw new Error('Enlace dañado o incompleto'); }
}

// --- Archivos: cabecera de texto + salto de línea + bytes cifrados ---
// Dentro del cifrado va el nombre y tipo del archivo (no se filtran).
export async function encryptFile(password, fileBytes, meta, alg) {
  const m = utf8(JSON.stringify({ name: meta.name, type: meta.type || '' }));
  const len = new Uint8Array(4);
  new DataView(len.buffer).setUint32(0, m.length);
  const { header, ciphertext } = await encryptBytes(password, concat(len, m, fileBytes), alg);
  return concat(utf8(header + '\n'), ciphertext);
}

export async function decryptFile(password, blobBytes) {
  const nl = blobBytes.indexOf(10);
  if (nl < 0 || nl > 400) throw new Error('No es un archivo .cifra');
  const header = fromUtf8(blobBytes.subarray(0, nl));
  const plain = await decryptBytes(password, header, blobBytes.subarray(nl + 1));
  const len = new DataView(plain.buffer, plain.byteOffset).getUint32(0);
  const meta = JSON.parse(fromUtf8(plain.subarray(4, 4 + len)));
  return { meta, data: plain.subarray(4 + len) };
}
