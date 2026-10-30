// Huellas (hashes) y HMAC.
import { sha3_256, sha3_512 } from '@noble/hashes/sha3';
import { getSodium } from './sodium.js';
import { hex, utf8 } from './encoding.js';

export const HASHES = ['SHA-256', 'SHA-384', 'SHA-512', 'SHA3-256', 'SHA3-512', 'BLAKE2b-256', 'BLAKE2b-512', 'SHA-1 (obsoleto)'];

export async function hashBytes(alg, data) {
  if (alg.startsWith('SHA3-256')) return hex(sha3_256(data));
  if (alg.startsWith('SHA3-512')) return hex(sha3_512(data));
  if (alg.startsWith('BLAKE2b')) {
    const s = await getSodium();
    return hex(s.crypto_generichash(alg.endsWith('512') ? 64 : 32, data));
  }
  const name = alg.startsWith('SHA-1') ? 'SHA-1' : alg;
  return hex(new Uint8Array(await crypto.subtle.digest(name, data)));
}

export async function hmac(alg, keyText, data) {
  const key = await crypto.subtle.importKey('raw', utf8(keyText), { name: 'HMAC', hash: alg }, false, ['sign']);
  return hex(new Uint8Array(await crypto.subtle.sign('HMAC', key, data)));
}
