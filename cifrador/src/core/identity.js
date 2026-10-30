// Identidad digital del usuario y cifrado de clave pública.
//
// Cada identidad contiene tres pares de claves:
//   - Ed25519     → firmar (demuestra quién envía el mensaje)
//   - X25519      → acuerdo de clave clásico (curva elíptica)
//   - ML-KEM-768  → acuerdo de clave post-cuántico (estándar NIST FIPS 203)
//
// Al cifrar para un contacto se combinan X25519 y ML-KEM ("híbrido"):
// un atacante tendría que romper LOS DOS para leer el mensaje. Es el mismo
// enfoque que usan hoy Signal (PQXDH), iMessage (PQ3) y Chrome (TLS).
import { ml_kem768 } from '@noble/post-quantum/ml-kem';
import { getSodium } from './sodium.js';
import { xchacha } from './symmetric.js';
import { utf8, fromUtf8, b64u, fromB64u, concat, randomBytes, hex } from './encoding.js';

const CTX_HYBRID = utf8('cifra-hibrido-v1');
const CTX_MSG = utf8('cifra-mensaje-firmado-v1');
const CTX_SIG = utf8('cifra-firma-texto-v1');

export async function generateIdentity(name) {
  const s = await getSodium();
  const ed = s.crypto_sign_keypair();
  const x = s.crypto_box_keypair();
  const kem = ml_kem768.keygen();
  return {
    name,
    created: new Date().toISOString(),
    edPk: b64u(ed.publicKey), edSk: b64u(ed.privateKey),
    xPk: b64u(x.publicKey), xSk: b64u(x.privateKey),
    kemPk: b64u(kem.publicKey), kemSk: b64u(kem.secretKey),
  };
}

export function publicKeyString(id) {
  return `cifrapub1.${b64u(utf8(id.name))}.${id.edPk}.${id.xPk}.${id.kemPk}`;
}

export async function parsePublicKey(str) {
  const p = str.trim().replace(/\s+/g, '').split('.');
  if (p.length !== 5 || p[0] !== 'cifrapub1') throw new Error('Clave pública no válida (debe empezar por "cifrapub1.")');
  const key = { name: fromUtf8(fromB64u(p[1])), ed: fromB64u(p[2]), x: fromB64u(p[3]), kem: fromB64u(p[4]) };
  if (key.ed.length !== 32 || key.x.length !== 32 || key.kem.length !== 1184) throw new Error('Clave pública dañada');
  key.fingerprint = await fingerprint(key.ed, key.x, key.kem);
  return key;
}

async function fingerprintBytes(ed, x, kem) {
  const s = await getSodium();
  return s.crypto_generichash(20, concat(ed, x, kem));
}

/** Huella digital: 40 caracteres para comparar en persona o por teléfono. */
export async function fingerprint(ed, x, kem) {
  return hex(await fingerprintBytes(ed, x, kem)).toUpperCase().match(/.{4}/g).join(' ');
}

export async function identityFingerprint(id) {
  return fingerprint(fromB64u(id.edPk), fromB64u(id.xPk), fromB64u(id.kemPk));
}

async function hybridKey(ss1, ss2, ephPk, kemCt, recipientX) {
  const s = await getSodium();
  return s.crypto_generichash(32, concat(ss1, ss2, ephPk, kemCt, recipientX), CTX_HYBRID);
}

/**
 * Cifra un texto para un destinatario. Si se pasa `sender`, el mensaje va
 * firmado; si no, es anónimo.
 */
export async function encryptTo(recipientPubStr, text, sender) {
  const s = await getSodium();
  const r = await parsePublicKey(recipientPubStr);
  const eph = s.crypto_box_keypair();
  const ss1 = s.crypto_scalarmult(eph.privateKey, r.x);
  const { cipherText: kemCt, sharedSecret: ss2 } = ml_kem768.encapsulate(r.kem);
  const key = await hybridKey(ss1, ss2, eph.publicKey, kemCt, r.x);

  const plain = utf8(text);
  let senderPk = new Uint8Array(32), sig = new Uint8Array(64);
  if (sender) {
    senderPk = fromB64u(sender.edPk);
    // La firma incluye la huella del destinatario: no se puede reenviar a otro
    // haciéndole creer que iba dirigido a él.
    const fp = await fingerprintBytes(r.ed, r.x, r.kem);
    sig = s.crypto_sign_detached(concat(CTX_MSG, fp, plain), fromB64u(sender.edSk));
  }
  const nonce = randomBytes(24);
  const header = `cifra1.pk.${b64u(eph.publicKey)}.${b64u(kemCt)}.${b64u(nonce)}`;
  const ct = await xchacha('encrypt', key, nonce, concat(senderPk, sig, plain), utf8(header));
  return `${header}.${b64u(ct)}`;
}

export async function decryptFrom(me, message) {
  const s = await getSodium();
  const p = message.trim().replace(/\s+/g, '').split('.');
  if (p.length !== 6 || p[0] !== 'cifra1' || p[1] !== 'pk') throw new Error('No es un mensaje para clave pública');
  const header = p.slice(0, 5).join('.');
  const ephPk = fromB64u(p[2]), kemCt = fromB64u(p[3]), nonce = fromB64u(p[4]);
  const myX = fromB64u(me.xPk);
  const ss1 = s.crypto_scalarmult(fromB64u(me.xSk), ephPk);
  const ss2 = ml_kem768.decapsulate(kemCt, fromB64u(me.kemSk));
  const key = await hybridKey(ss1, ss2, ephPk, kemCt, myX);
  let inner;
  try { inner = await xchacha('decrypt', key, nonce, fromB64u(p[5]), utf8(header)); }
  catch { throw new Error('Este mensaje no es para ti o ha sido alterado'); }

  const senderPk = inner.slice(0, 32), sig = inner.slice(32, 96), plain = inner.slice(96);
  const anonymous = senderPk.every((b) => b === 0);
  let verified = false;
  if (!anonymous) {
    const fp = await fingerprintBytes(fromB64u(me.edPk), myX, fromB64u(me.kemPk));
    verified = s.crypto_sign_verify_detached(sig, concat(CTX_MSG, fp, plain), senderPk);
  }
  return { text: fromUtf8(plain), anonymous, verified, senderEdPk: b64u(senderPk) };
}

// --- Firmas de texto independientes ---
export async function signText(me, text) {
  const s = await getSodium();
  const sig = s.crypto_sign_detached(concat(CTX_SIG, utf8(text)), fromB64u(me.edSk));
  return `cifrasig1.${me.edPk}.${b64u(sig)}`;
}

export async function verifyText(text, signature) {
  const s = await getSodium();
  const p = signature.trim().split('.');
  if (p.length !== 3 || p[0] !== 'cifrasig1') throw new Error('Firma no válida (debe empezar por "cifrasig1.")');
  const ok = s.crypto_sign_verify_detached(fromB64u(p[2]), concat(CTX_SIG, utf8(text)), fromB64u(p[1]));
  return { ok, signerEdPk: p[1] };
}

export { randomBytes };
