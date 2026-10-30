// Certificados X.509 (los que usan HTTPS, firma de correo S/MIME, VPN, etc.).
import 'reflect-metadata';
import * as x509 from '@peculiar/x509';
import { hex } from './encoding.js';

x509.cryptoProvider.set(crypto);

export const KEY_TYPES = {
  'ECDSA P-256': { name: 'ECDSA', namedCurve: 'P-256', hash: 'SHA-256' },
  'ECDSA P-384': { name: 'ECDSA', namedCurve: 'P-384', hash: 'SHA-384' },
  'RSA 3072': { name: 'RSASSA-PKCS1-v1_5', modulusLength: 3072, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  'RSA 4096': { name: 'RSASSA-PKCS1-v1_5', modulusLength: 4096, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  'Ed25519': { name: 'Ed25519' },
};

const esc = (v) => v.replace(/([,+"\\<>;=])/g, '\\$1');

function buildName({ cn, o, ou, c, email }) {
  const parts = [];
  if (cn) parts.push(`CN=${esc(cn)}`);
  if (o) parts.push(`O=${esc(o)}`);
  if (ou) parts.push(`OU=${esc(ou)}`);
  if (c) parts.push(`C=${esc(c.toUpperCase().slice(0, 2))}`);
  if (email) parts.push(`E=${esc(email)}`);
  if (!parts.length) throw new Error('Indica al menos el nombre común (CN)');
  return parts.join(', ');
}

function sanEntries(list) {
  return (list || '').split(',').map((v) => v.trim()).filter(Boolean).map((v) => {
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(v)) return { type: 'ip', value: v };
    if (v.includes('@')) return { type: 'email', value: v };
    return { type: 'dns', value: v };
  });
}

function serial() {
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[0] &= 0x7f;
  return hex(b);
}

async function exportPrivate(key) {
  const der = await crypto.subtle.exportKey('pkcs8', key);
  return x509.PemConverter.encode(der, 'PRIVATE KEY');
}

/**
 * Crea un certificado autofirmado. Con `isCA` sirve como autoridad
 * certificadora para firmar otros certificados.
 */
export async function createSelfSigned(opts) {
  const alg = KEY_TYPES[opts.keyType];
  const keys = await crypto.subtle.generateKey(alg, true, ['sign', 'verify']);
  const name = buildName(opts);
  const now = new Date();
  const ext = [
    new x509.BasicConstraintsExtension(!!opts.isCA, opts.isCA ? 1 : undefined, true),
    new x509.KeyUsagesExtension(opts.isCA
      ? x509.KeyUsageFlags.keyCertSign | x509.KeyUsageFlags.cRLSign | x509.KeyUsageFlags.digitalSignature
      : x509.KeyUsageFlags.digitalSignature | x509.KeyUsageFlags.keyEncipherment, true),
    await x509.SubjectKeyIdentifierExtension.create(keys.publicKey),
  ];
  const san = sanEntries(opts.san);
  if (san.length) ext.push(new x509.SubjectAlternativeNameExtension(san));
  if (!opts.isCA) ext.push(new x509.ExtendedKeyUsageExtension([x509.ExtendedKeyUsage.serverAuth, x509.ExtendedKeyUsage.clientAuth]));

  const cert = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: serial(), name, notBefore: now,
    notAfter: new Date(now.getTime() + (opts.days || 365) * 86400000),
    signingAlgorithm: alg, keys, extensions: ext,
  });
  return { certPem: cert.toString('pem'), keyPem: await exportPrivate(keys.privateKey), cert, keys, alg };
}

/** Emite un certificado de servidor/cliente firmado por una CA creada antes. */
export async function issueFromCA(ca, opts) {
  const alg = KEY_TYPES[opts.keyType];
  const keys = await crypto.subtle.generateKey(alg, true, ['sign', 'verify']);
  const now = new Date();
  const ext = [
    new x509.BasicConstraintsExtension(false, undefined, true),
    new x509.KeyUsagesExtension(x509.KeyUsageFlags.digitalSignature | x509.KeyUsageFlags.keyEncipherment, true),
    new x509.ExtendedKeyUsageExtension([x509.ExtendedKeyUsage.serverAuth, x509.ExtendedKeyUsage.clientAuth]),
    await x509.SubjectKeyIdentifierExtension.create(keys.publicKey),
    await x509.AuthorityKeyIdentifierExtension.create(ca.cert),
  ];
  const san = sanEntries(opts.san);
  if (san.length) ext.push(new x509.SubjectAlternativeNameExtension(san));
  const cert = await x509.X509CertificateGenerator.create({
    serialNumber: serial(), subject: buildName(opts), issuer: ca.cert.subject,
    notBefore: now, notAfter: new Date(now.getTime() + (opts.days || 365) * 86400000),
    signingAlgorithm: ca.alg, publicKey: keys.publicKey, signingKey: ca.keys.privateKey, extensions: ext,
  });
  return { certPem: cert.toString('pem'), keyPem: await exportPrivate(keys.privateKey) };
}

/** Solicitud de firma (CSR) para enviar a una autoridad real (Let's Encrypt, etc.). */
export async function createCSR(opts) {
  const alg = KEY_TYPES[opts.keyType];
  const keys = await crypto.subtle.generateKey(alg, true, ['sign', 'verify']);
  const ext = [];
  const san = sanEntries(opts.san);
  if (san.length) ext.push(new x509.SubjectAlternativeNameExtension(san));
  const csr = await x509.Pkcs10CertificateRequestGenerator.create({
    name: buildName(opts), keys, signingAlgorithm: alg, extensions: ext,
  });
  return { csrPem: csr.toString('pem'), keyPem: await exportPrivate(keys.privateKey) };
}

/** Lee un certificado PEM y devuelve sus datos principales. */
export async function inspect(pem) {
  const cert = new x509.X509Certificate(pem.trim());
  const fp = new Uint8Array(await cert.getThumbprint('SHA-256'));
  const now = new Date();
  return {
    subject: cert.subject, issuer: cert.issuer, serial: cert.serialNumber,
    notBefore: cert.notBefore.toLocaleString(), notAfter: cert.notAfter.toLocaleString(),
    valid: now >= cert.notBefore && now <= cert.notAfter,
    selfSigned: await cert.isSelfSigned(),
    algorithm: cert.signatureAlgorithm.name + (cert.signatureAlgorithm.hash ? ' / ' + cert.signatureAlgorithm.hash.name : ''),
    sha256: hex(fp).toUpperCase().match(/../g).join(':'),
    san: cert.getExtension(x509.SubjectAlternativeNameExtension)?.names.items.map((n) => `${n.type}:${n.value}`).join(', ') || '—',
  };
}
