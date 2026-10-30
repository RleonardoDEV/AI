import { describe, it, expect } from 'vitest';
import * as sym from '../src/core/symmetric.js';
import * as id from '../src/core/identity.js';
import * as pgp from '../src/core/pgp.js';
import * as certs from '../src/core/certs.js';
import * as tools from '../src/core/tools.js';
import { hashBytes, hmac } from '../src/core/hash.js';
import { utf8 } from '../src/core/encoding.js';

describe('cifrado con contraseña', () => {
  for (const alg of ['xc', 'ag', 'cc']) {
    it(`${alg}: cifra, descifra y rechaza errores`, async () => {
      const msg = await sym.encryptText('clave segura', 'Hola ñandú 🔐', alg);
      expect(msg.startsWith(`cifra1.${alg}.`)).toBe(true);
      expect(await sym.decryptText('clave segura', msg)).toBe('Hola ñandú 🔐');
      await expect(sym.decryptText('otra', msg)).rejects.toThrow(/incorrecta/);
      const tampered = msg.slice(0, -3) + (msg.at(-3) === 'A' ? 'B' : 'A') + msg.slice(-2);
      await expect(sym.decryptText('clave segura', tampered)).rejects.toThrow();
    }, 30000);
  }
  it('la cabecera está autenticada', async () => {
    const msg = await sym.encryptText('k', 'x', 'ag');
    await expect(sym.decryptText('k', msg.replace('.p600000.', '.p600001.'))).rejects.toThrow();
  }, 30000);
  it('archivos', async () => {
    const data = crypto.getRandomValues(new Uint8Array(5000));
    const blob = await sym.encryptFile('pw', data, { name: 'foto.jpg', type: 'image/jpeg' }, 'cc');
    const out = await sym.decryptFile('pw', blob);
    expect(out.meta.name).toBe('foto.jpg');
    expect(out.data).toEqual(data);
  }, 30000);
  it('enlaces con clave aleatoria', async () => {
    const { key, message } = await sym.encryptWithRandomKey('https://ejemplo.com');
    expect(await sym.decryptWithKey(key, message)).toBe('https://ejemplo.com');
  });
});

describe('identidad híbrida post-cuántica', () => {
  it('cifra, firma y verifica', async () => {
    const ana = await id.generateIdentity('Ana');
    const luis = await id.generateIdentity('Luis');
    const msg = await id.encryptTo(id.publicKeyString(luis), 'secreto', ana);
    const out = await id.decryptFrom(luis, msg);
    expect(out).toMatchObject({ text: 'secreto', verified: true, anonymous: false, senderEdPk: ana.edPk });
    await expect(id.decryptFrom(ana, msg)).rejects.toThrow(/no es para ti/);
    const anon = await id.decryptFrom(luis, await id.encryptTo(id.publicKeyString(luis), 'hola'));
    expect(anon.anonymous).toBe(true);
    const pk = await id.parsePublicKey(id.publicKeyString(ana));
    expect(pk.fingerprint).toBe(await id.identityFingerprint(ana));
  });
  it('firmas de texto', async () => {
    const ana = await id.generateIdentity('Ana');
    const sig = await id.signText(ana, 'contrato');
    expect((await id.verifyText('contrato', sig)).ok).toBe(true);
    expect((await id.verifyText('contrato!', sig)).ok).toBe(false);
  });
});

describe('OpenPGP', () => {
  it('genera, cifra, firma y verifica', async () => {
    const k = await pgp.generateKey('Ana', 'ana@ejemplo.com', 'pp');
    const armored = await pgp.encrypt({ text: 'hola', publicKeys: k.publicKey, privateKey: k.privateKey, passphrase: 'pp' });
    const out = await pgp.decrypt({ armored, privateKey: k.privateKey, passphrase: 'pp', senderPublicKey: k.publicKey });
    expect(out).toEqual({ text: 'hola', signature: 'firma válida' });
    const sym2 = await pgp.encrypt({ text: 'x', password: 'abc' });
    expect((await pgp.decrypt({ armored: sym2, password: 'abc' })).text).toBe('x');
    const signed = await pgp.sign('acuerdo', k.privateKey, 'pp');
    expect((await pgp.verify(signed, k.publicKey)).ok).toBe(true);
    expect((await pgp.keyInfo(k.publicKey)).users[0]).toContain('Ana');
  }, 30000);
});

describe('certificados', () => {
  it('autofirmado, CA y CSR', async () => {
    const ca = await certs.createSelfSigned({ cn: 'Mi CA', o: 'Casa', keyType: 'ECDSA P-256', isCA: true, days: 3650 });
    const leaf = await certs.issueFromCA(ca, { cn: 'servidor.local', keyType: 'ECDSA P-256', san: 'servidor.local, 192.168.1.10' });
    const info = await certs.inspect(leaf.certPem);
    expect(info.issuer).toContain('Mi CA');
    expect(info.san).toContain('192.168.1.10');
    expect(leaf.keyPem).toContain('PRIVATE KEY');
    const csr = await certs.createCSR({ cn: 'web.com', keyType: 'RSA 3072', san: 'web.com' });
    expect(csr.csrPem).toContain('CERTIFICATE REQUEST');
    const ed = await certs.createSelfSigned({ cn: 'ed', keyType: 'Ed25519' });
    expect((await certs.inspect(ed.certPem)).selfSigned).toBe(true);
  }, 60000);
});

describe('herramientas', () => {
  it('hashes conocidos', async () => {
    expect(await hashBytes('SHA-256', utf8('abc'))).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(await hashBytes('SHA3-256', utf8('abc'))).toBe('3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532');
    expect((await hmac('SHA-256', 'k', utf8('m'))).length).toBe(64);
  });
  it('contraseñas, clásicos, codificaciones y esteganografía', () => {
    const p = tools.generatePassword(20, { lower: 1, upper: 1, digits: 1, symbols: 1 });
    expect(p.password).toHaveLength(20);
    expect(tools.CLASSICAL['Vigenère']('Ataque al alba', 'limon', false)).toBe('Lbmehp ix oymi');
    expect(tools.CLASSICAL['Vigenère']('Lbmehp ix oymi', 'limon', true)).toBe('Ataque al alba');
    for (const [, e] of Object.entries(tools.ENCODINGS)) expect(e.dec(e.enc('ñ€ 1'))).toBe('ñ€ 1');
    const hidden = tools.hideInText('Nos vemos mañana', 'cifra1.xc.secreto');
    expect(tools.stripHidden(hidden)).toBe('Nos vemos mañana');
    expect(tools.revealFromText(hidden)).toBe('cifra1.xc.secreto');
  });
});
