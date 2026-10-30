// OpenPGP: compatible con GnuPG, Kleopatra, Thunderbird, OpenKeychain, Proton…
import * as openpgp from 'openpgp';

export async function generateKey(name, email, passphrase) {
  const { privateKey, publicKey, revocationCertificate } = await openpgp.generateKey({
    type: 'curve25519', userIDs: [{ name, email }], passphrase: passphrase || undefined, format: 'armored',
  });
  return { privateKey, publicKey, revocationCertificate };
}

async function readPublicKeys(armored) {
  return openpgp.readKeys({ armoredKeys: armored });
}

async function unlockPrivate(armored, passphrase) {
  const key = await openpgp.readPrivateKey({ armoredKey: armored });
  if (key.isDecrypted()) return key;
  if (!passphrase) throw new Error('Esta clave privada necesita su contraseña');
  return openpgp.decryptKey({ privateKey: key, passphrase });
}

export async function keyInfo(armored) {
  const key = await openpgp.readKey({ armoredKey: armored });
  return {
    users: key.getUserIDs(),
    fingerprint: key.getFingerprint().toUpperCase().match(/.{4}/g).join(' '),
    algorithm: key.getAlgorithmInfo().algorithm,
    created: key.getCreationTime().toLocaleString(),
    isPrivate: key.isPrivate(),
  };
}

export async function encrypt({ text, publicKeys, password, privateKey, passphrase }) {
  const opts = { message: await openpgp.createMessage({ text }) };
  if (publicKeys?.trim()) opts.encryptionKeys = await readPublicKeys(publicKeys);
  if (password) opts.passwords = [password];
  if (!opts.encryptionKeys && !opts.passwords) throw new Error('Indica la clave pública del destinatario o una contraseña');
  if (privateKey?.trim()) opts.signingKeys = await unlockPrivate(privateKey, passphrase);
  return openpgp.encrypt(opts);
}

export async function decrypt({ armored, privateKey, passphrase, password, senderPublicKey }) {
  const opts = { message: await openpgp.readMessage({ armoredMessage: armored }) };
  if (privateKey?.trim()) opts.decryptionKeys = await unlockPrivate(privateKey, passphrase);
  if (password) opts.passwords = [password];
  if (senderPublicKey?.trim()) opts.verificationKeys = await readPublicKeys(senderPublicKey);
  const { data, signatures } = await openpgp.decrypt(opts);
  let signature = 'sin firma';
  if (signatures.length && opts.verificationKeys) {
    try { await signatures[0].verified; signature = 'firma válida'; } catch { signature = 'FIRMA NO VÁLIDA'; }
  } else if (signatures.length) signature = 'firmado (añade la clave pública del remitente para comprobarlo)';
  return { text: data, signature };
}

export async function sign(text, privateKey, passphrase) {
  const message = await openpgp.createCleartextMessage({ text });
  return openpgp.sign({ message, signingKeys: await unlockPrivate(privateKey, passphrase) });
}

export async function verify(cleartext, publicKey) {
  const message = await openpgp.readCleartextMessage({ cleartextMessage: cleartext });
  const res = await openpgp.verify({ message, verificationKeys: await readPublicKeys(publicKey) });
  try { await res.signatures[0].verified; return { ok: true, text: res.data }; }
  catch { return { ok: false, text: res.data }; }
}
