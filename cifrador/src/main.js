import * as sym from './core/symmetric.js';
import * as ident from './core/identity.js';
import { HASHES, hashBytes, hmac } from './core/hash.js';
import * as tools from './core/tools.js';
import { utf8 } from './core/encoding.js';
import { getSodium } from './core/sodium.js';

// Módulos grandes: se cargan solo cuando hacen falta.
const loadPgp = () => import('./core/pgp.js');
const loadCerts = () => import('./core/certs.js');
const loadQR = () => import('qrcode').then((m) => m.default || m);

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// ---------- utilidades de interfaz ----------
function toast(msg) {
  const t = $('toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(toast.t); toast.t = setTimeout(() => t.classList.remove('show'), 2200);
}

async function copy(text) {
  try { await navigator.clipboard.writeText(text); toast('Copiado'); }
  catch { toast('No se pudo copiar: selecciónalo y cópialo a mano'); }
}

/** Muestra un resultado con botones de copiar, compartir y QR. */
function result(outId, { label, text, note, qr = true, extra = '' }) {
  const out = $(outId);
  out.innerHTML = `${note ? `<p>${note}</p>` : ''}<label>${esc(label)}<textarea readonly rows="5"></textarea></label>
    <div class="row"><button data-a="copy">Copiar</button>${navigator.share ? '<button data-a="share">Compartir</button>' : ''}${qr ? '<button data-a="qr">QR</button>' : ''}</div>
    <div class="qr"></div>${extra}`;
  out.querySelector('textarea').value = text;
  out.querySelector('[data-a=copy]').onclick = () => copy(text);
  out.querySelector('[data-a=share]')?.addEventListener('click', () => navigator.share({ text }).catch(() => {}));
  out.querySelector('[data-a=qr]')?.addEventListener('click', () => renderQR(out.querySelector('.qr'), text));
}

async function renderQR(el, text) {
  try {
    const QR = await loadQR();
    el.innerHTML = `<img alt="Código QR" src="${await QR.toDataURL(text, { errorCorrectionLevel: 'L', margin: 1, width: 320 })}">`;
  } catch { el.innerHTML = '<p class="err">Demasiado largo para un código QR</p>'; }
}

const showErr = (outId, e) => { $(outId).innerHTML = `<p class="err">${esc(e.message || e)}</p>`; };
const showMsg = (outId, html) => { $(outId).innerHTML = html; };

/** Ejecuta una acción: desactiva el botón mientras trabaja y muestra errores. */
function on(btnId, outId, fn) {
  $(btnId).addEventListener('click', async (ev) => {
    const b = ev.currentTarget; const old = b.textContent;
    b.disabled = true; b.textContent = 'Procesando…';
    try { await fn(); } catch (e) { console.error(e); showErr(outId, e); }
    finally { b.disabled = false; b.textContent = old; }
  });
}

function download(bytes, name, type = 'application/octet-stream') {
  const url = URL.createObjectURL(new Blob([bytes], { type }));
  const a = Object.assign(document.createElement('a'), { href: url, download: name });
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

const fill = (sel, items) => { $(sel).innerHTML = items.map(([v, t]) => `<option value="${esc(v)}">${esc(t)}</option>`).join(''); };

// ---------- pestañas ----------
function openTab(name) {
  document.querySelectorAll('.tabs button').forEach((b) => b.classList.toggle('active', b.dataset.tab === name));
  document.querySelectorAll('.panel').forEach((p) => p.classList.toggle('active', p.id === name));
}
document.querySelectorAll('.tabs button').forEach((b) => b.addEventListener('click', () => openTab(b.dataset.tab)));

// ---------- TEXTO ----------
const algOptions = Object.entries(sym.ALGORITHMS).map(([k, v]) => [k, v.name]);
fill('t-alg', algOptions); fill('f-alg', algOptions);
const updateNote = () => { $('t-alg-note').textContent = sym.ALGORITHMS[$('t-alg').value].note; };
$('t-alg').onchange = updateNote; updateNote();
$('t-pw').oninput = () => {
  const s = tools.estimateStrength($('t-pw').value);
  $('t-meter').style.width = Math.min(100, s.bits / 1.2) + '%';
  $('t-meter').title = `${s.label} (~${s.bits} bits)`;
};
on('t-enc', 't-out', async () => {
  const text = $('t-in').value;
  if (!text) throw new Error('Escribe un texto');
  result('t-out', { label: 'Mensaje cifrado', text: await sym.encryptText($('t-pw').value, text, $('t-alg').value) });
});
on('t-dec', 't-out', async () => {
  result('t-out', { label: 'Texto descifrado', text: await sym.decryptText($('t-pw').value, $('t-in').value), qr: false,
    note: '<span class="ok">✔ Descifrado y verificado: el mensaje no ha sido alterado.</span>' });
});

// ---------- ARCHIVOS ----------
async function readFile(inputId) {
  const f = $(inputId).files[0];
  if (!f) throw new Error('Elige un archivo');
  if (f.size > 500 * 1024 * 1024) throw new Error('Archivo demasiado grande (máximo 500 MB)');
  return { f, bytes: new Uint8Array(await f.arrayBuffer()) };
}
on('f-enc', 'f-out', async () => {
  const { f, bytes } = await readFile('f-file');
  const out = await sym.encryptFile($('f-pw').value, bytes, { name: f.name, type: f.type }, $('f-alg').value);
  const name = `${crypto.randomUUID().slice(0, 8)}.cifra`;
  download(out, name);
  showMsg('f-out', `<p class="ok">✔ Archivo cifrado y descargado como <code>${name}</code>.</p>`);
});
on('f-dec', 'f-out', async () => {
  const { bytes } = await readFile('f-file');
  const { meta, data } = await sym.decryptFile($('f-pw').value, bytes);
  download(data, meta.name, meta.type || undefined);
  showMsg('f-out', `<p class="ok">✔ Descifrado: <code>${esc(meta.name)}</code> (${data.length.toLocaleString()} bytes).</p>`);
});

// ---------- ENLACE SEGURO ----------
$('l-base').value = location.href.split('#')[0];
$('l-mode').onchange = () => { $('l-pw-wrap').hidden = $('l-mode').value !== 'pw'; };
on('l-make', 'l-out', async () => {
  const text = $('l-in').value.trim();
  if (!text) throw new Error('Escribe un texto o enlace');
  const base = $('l-base').value.split('#')[0];
  let link;
  if ($('l-mode').value === 'key') {
    const { key, message } = await sym.encryptWithRandomKey(text);
    link = `${base}#m=${message}&k=${key}`;
  } else {
    link = `${base}#m=${await sym.encryptText($('l-pw').value, text, 'xc')}`;
  }
  result('l-out', { label: 'Enlace seguro', text: link,
    note: $('l-mode').value === 'pw' ? 'Envía la contraseña por otro canal (por ejemplo, en una llamada).' : 'Cualquiera con este enlace completo puede leerlo. Compártelo solo con quien quieras.' });
});

function parseLink(str) {
  const h = str.includes('#') ? str.slice(str.indexOf('#') + 1) : str;
  const p = new URLSearchParams(h);
  if (!p.get('m')) throw new Error('El enlace no contiene un mensaje cifrado');
  return { m: p.get('m'), k: p.get('k') };
}
$('l-open-in').oninput = () => {
  try { $('l-open-pw-wrap').hidden = !!parseLink($('l-open-in').value).k; } catch { /* aún incompleto */ }
};
on('l-open', 'l-open-out', async () => {
  const { m, k } = parseLink($('l-open-in').value);
  const text = k ? await sym.decryptWithKey(k, m) : await sym.decryptText($('l-open-pw').value, m);
  const isUrl = /^https?:\/\/\S+$/i.test(text);
  result('l-open-out', { label: 'Contenido', text, qr: false,
    extra: isUrl ? `<p class="hint">Es un enlace. Comprueba que confías en él antes de abrirlo:</p><a href="${esc(text)}" target="_blank" rel="noopener noreferrer">${esc(text)}</a>` : '' });
});
// Si la app se abrió desde un enlace seguro, lo carga directamente.
if (location.hash.includes('m=cifra1')) {
  openTab('enlace');
  $('l-open-in').value = location.href;
  $('l-open-in').dispatchEvent(new Event('input'));
  history.replaceState(null, '', location.pathname + location.search); // quita la clave de la barra
  if (!$('l-open-pw-wrap').hidden) $('l-open-pw').focus(); else $('l-open').click();
}

// ---------- IDENTIDAD Y CONVERSACIONES ----------
const store = {
  get: (k) => { try { return localStorage.getItem(k); } catch { return null; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch { toast('No se pudo guardar en este navegador'); } },
  del: (k) => { try { localStorage.removeItem(k); } catch { /* nada */ } },
};
let me = null;
const contacts = () => JSON.parse(store.get('cifra.contacts') || '[]');
const saveContacts = (c) => store.set('cifra.contacts', JSON.stringify(c));

async function renderIdentity() {
  const has = !!store.get('cifra.identity');
  $('id-none').hidden = has; $('id-locked').hidden = !has || !!me; $('id-ready').hidden = !me;
  if (!me) return;
  $('id-label').textContent = me.name;
  $('id-fp').textContent = await ident.identityFingerprint(me);
  const list = contacts();
  $('c-list').innerHTML = list.length ? list.map((c, i) => `<li><span><strong>${esc(c.name)}</strong><br><code>${esc(c.fp)}</code></span><button data-del="${i}">Quitar</button></li>`).join('') : '<li class="hint">Aún no tienes contactos.</li>';
  $('c-list').querySelectorAll('[data-del]').forEach((b) => b.onclick = () => { const l = contacts(); l.splice(+b.dataset.del, 1); saveContacts(l); renderIdentity(); });
  fill('m-to', list.map((c, i) => [i, c.name]));
}

on('id-create', 'm-out', async () => {
  const name = $('id-name').value.trim(), pw = $('id-pw').value;
  if (!name) throw new Error('Escribe tu nombre');
  if (pw.length < 8) throw new Error('Usa una contraseña de al menos 8 caracteres');
  me = await ident.generateIdentity(name);
  store.set('cifra.identity', await sym.encryptText(pw, JSON.stringify(me), 'xc'));
  $('id-pw').value = '';
  await renderIdentity();
  toast('Identidad creada. Haz una copia de seguridad.');
});
on('id-unlock', 'm-out', async () => {
  me = JSON.parse(await sym.decryptText($('id-unlock-pw').value, store.get('cifra.identity')));
  $('id-unlock-pw').value = '';
  await renderIdentity();
});
$('id-lock').onclick = () => { me = null; $('m-out').innerHTML = ''; renderIdentity(); };
$('id-delete').onclick = () => {
  if (confirm('¿Borrar tu identidad de este dispositivo? Si no tienes copia de seguridad, no podrás leer los mensajes que te envíen.')) {
    store.del('cifra.identity'); me = null; renderIdentity();
  }
};
$('id-copy').onclick = () => copy(ident.publicKeyString(me));
$('id-qr').onclick = () => renderQR($('id-qr-out'), ident.publicKeyString(me));
$('id-backup').onclick = () => {
  const blob = store.get('cifra.identity');
  download(utf8(blob), `identidad-cifra-${me.name}.txt`, 'text/plain');
  toast('Copia guardada (protegida con tu contraseña)');
};
on('id-restore', 'm-out', async () => {
  const blob = $('id-restore-in').value.trim();
  const data = JSON.parse(await sym.decryptText($('id-restore-pw').value, blob));
  if (!data.edSk || !data.kemSk) throw new Error('No es una copia de identidad');
  store.set('cifra.identity', blob); me = data;
  await renderIdentity(); toast('Identidad restaurada');
});
on('c-add', 'm-out', async () => {
  const pub = $('c-pub').value.trim();
  const k = await ident.parsePublicKey(pub);
  const list = contacts();
  if (list.some((c) => c.fp === k.fingerprint)) throw new Error('Ese contacto ya existe');
  list.push({ name: k.name, pub, fp: k.fingerprint, edPk: pub.split('.')[2] });
  saveContacts(list); $('c-pub').value = '';
  await renderIdentity(); toast(`Contacto ${k.name} añadido`);
});
on('m-enc', 'm-out', async () => {
  const c = contacts()[$('m-to').value];
  if (!c) throw new Error('Añade primero un contacto');
  if (!$('m-in').value) throw new Error('Escribe un mensaje');
  result('m-out', { label: `Mensaje cifrado para ${c.name}`, text: await ident.encryptTo(c.pub, $('m-in').value, $('m-anon').checked ? null : me) });
});
on('m-dec', 'm-out', async () => {
  const r = await ident.decryptFrom(me, $('m-in').value);
  const sender = contacts().find((c) => c.edPk === r.senderEdPk);
  const note = r.anonymous ? '<span class="warn">Mensaje anónimo: no se puede saber quién lo envió.</span>'
    : !r.verified ? '<span class="err">⚠ La firma NO es válida. No te fíes de este mensaje.</span>'
      : sender ? `<span class="ok">✔ Firmado por ${esc(sender.name)} (verificado)</span>`
        : '<span class="warn">Firma válida, pero de alguien que no está en tus contactos.</span>';
  result('m-out', { label: 'Mensaje', text: r.text, note, qr: false });
});
on('s-sign', 's-out', async () => {
  if (!$('s-in').value) throw new Error('Escribe un texto');
  const sig = await ident.signText(me, $('s-in').value);
  $('s-sig').value = sig;
  result('s-out', { label: 'Firma (compártela junto al texto)', text: sig });
});
on('s-verify', 's-out', async () => {
  const r = await ident.verifyText($('s-in').value, $('s-sig').value);
  const who = contacts().find((c) => c.edPk === r.signerEdPk)?.name || (me && me.edPk === r.signerEdPk ? 'ti' : null);
  showMsg('s-out', r.ok ? `<p class="ok">✔ Firma válida${who ? ` de ${esc(who)}` : ' (de alguien que no está en tus contactos)'}. El texto no ha cambiado.</p>` : '<p class="err">✘ Firma NO válida: el texto fue modificado o la firma no corresponde.</p>');
});

// ---------- OPENPGP ----------
on('p-gen', 'p-gen-out', async () => {
  const pgp = await loadPgp();
  if (!$('p-name').value) throw new Error('Escribe un nombre');
  const k = await pgp.generateKey($('p-name').value, $('p-email').value, $('p-pass').value);
  const out = $('p-gen-out');
  out.innerHTML = '<div id="pg1"></div><div id="pg2"></div><div id="pg3"></div>';
  result('pg1', { label: 'Clave PÚBLICA (compártela)', text: k.publicKey, qr: false });
  result('pg2', { label: 'Clave PRIVADA (guárdala en secreto)', text: k.privateKey, qr: false });
  result('pg3', { label: 'Certificado de revocación (por si pierdes la clave)', text: k.revocationCertificate, qr: false });
  $('p-priv').value = k.privateKey;
});
const pgpArgs = () => ({ publicKeys: $('p-pub').value, privateKey: $('p-priv').value, passphrase: $('p-priv-pass').value, password: $('p-sym').value });
on('p-enc', 'p-out', async () => {
  const pgp = await loadPgp(); const a = pgpArgs();
  result('p-out', { label: 'Mensaje PGP', qr: false, text: await pgp.encrypt({ text: $('p-text').value, publicKeys: a.publicKeys, password: a.password, privateKey: a.privateKey, passphrase: a.passphrase }) });
});
on('p-dec', 'p-out', async () => {
  const pgp = await loadPgp(); const a = pgpArgs();
  const r = await pgp.decrypt({ armored: $('p-text').value, privateKey: a.privateKey, passphrase: a.passphrase, password: a.password, senderPublicKey: a.publicKeys });
  result('p-out', { label: 'Texto descifrado', text: r.text, qr: false, note: `Firma: <strong>${esc(r.signature)}</strong>` });
});
on('p-sign', 'p-out', async () => {
  const pgp = await loadPgp(); const a = pgpArgs();
  result('p-out', { label: 'Texto firmado', qr: false, text: await pgp.sign($('p-text').value, a.privateKey, a.passphrase) });
});
on('p-verify', 'p-out', async () => {
  const pgp = await loadPgp();
  const r = await pgp.verify($('p-text').value, $('p-pub').value);
  showMsg('p-out', r.ok ? '<p class="ok">✔ Firma válida</p>' : '<p class="err">✘ Firma NO válida</p>');
});
on('p-info', 'p-out', async () => {
  const pgp = await loadPgp();
  const src = $('p-pub').value.trim() || $('p-priv').value.trim();
  if (!src) throw new Error('Pega una clave en el campo de clave pública o privada');
  const i = await pgp.keyInfo(src);
  showMsg('p-out', `<p><strong>${esc(i.users.join(', '))}</strong> (${i.isPrivate ? 'privada' : 'pública'})<br>Huella: <code>${esc(i.fingerprint)}</code><br>Algoritmo: ${esc(i.algorithm)} · Creada: ${esc(i.created)}</p>`);
});

// ---------- CERTIFICADOS ----------
fill('x-key', ['ECDSA P-256', 'ECDSA P-384', 'RSA 3072', 'RSA 4096', 'Ed25519'].map((k) => [k, k]));
const certOpts = () => ({ cn: $('x-cn').value.trim(), o: $('x-o').value.trim(), ou: $('x-ou').value.trim(), c: $('x-c').value.trim(), email: $('x-email').value.trim(), san: $('x-san').value, keyType: $('x-key').value, days: +$('x-days').value || 365 });
const pemBlock = (id, label, text, file) => `<label>${esc(label)}<textarea readonly rows="5" id="${id}"></textarea></label><div class="row"><button data-copy="${id}">Copiar</button><button data-dl="${id}" data-file="${file}">Descargar</button></div>`;
function showPems(blocks) {
  const out = $('x-out');
  out.innerHTML = blocks.map(([id, label, , file]) => pemBlock(id, label, '', file)).join('');
  blocks.forEach(([id, , text]) => { $(id).value = text; });
  out.querySelectorAll('[data-copy]').forEach((b) => b.onclick = () => copy($(b.dataset.copy).value));
  out.querySelectorAll('[data-dl]').forEach((b) => b.onclick = () => download(utf8($(b.dataset.dl).value), b.dataset.file, 'application/x-pem-file'));
}
on('x-gen', 'x-out', async () => {
  const certs = await loadCerts(); const o = certOpts(); const kind = $('x-kind').value;
  if (kind === 'self') {
    const r = await certs.createSelfSigned(o);
    showPems([['x1', 'Certificado', r.certPem, 'certificado.crt'], ['x2', 'Clave privada (secreta)', r.keyPem, 'clave-privada.key']]);
  } else if (kind === 'ca') {
    const ca = await certs.createSelfSigned({ ...o, cn: `${o.cn || 'Mi'} CA`, san: '', isCA: true, days: Math.max(o.days, 3650) });
    const leaf = await certs.issueFromCA(ca, o);
    showPems([['x1', 'Certificado de la CA (instálalo como "de confianza" en tus dispositivos)', ca.certPem, 'ca.crt'], ['x2', 'Clave privada de la CA (guárdala muy bien)', ca.keyPem, 'ca.key'],
      ['x3', 'Certificado del servidor', leaf.certPem, 'servidor.crt'], ['x4', 'Clave privada del servidor', leaf.keyPem, 'servidor.key']]);
  } else {
    const r = await certs.createCSR(o);
    showPems([['x1', 'Solicitud (CSR): envíala a la autoridad', r.csrPem, 'solicitud.csr'], ['x2', 'Clave privada (secreta)', r.keyPem, 'clave-privada.key']]);
  }
});
on('x-inspect', 'x-inspect-out', async () => {
  const certs = await loadCerts();
  const i = await certs.inspect($('x-inspect-in').value);
  showMsg('x-inspect-out', `<p><strong>Titular:</strong> ${esc(i.subject)}<br><strong>Emisor:</strong> ${esc(i.issuer)}${i.selfSigned ? ' (autofirmado)' : ''}<br>
    <strong>Válido:</strong> ${esc(i.notBefore)} → ${esc(i.notAfter)} ${i.valid ? '<span class="ok">✔ vigente</span>' : '<span class="err">✘ caducado o aún no válido</span>'}<br>
    <strong>Nombres:</strong> ${esc(i.san)}<br><strong>Algoritmo:</strong> ${esc(i.algorithm)}<br><strong>Nº de serie:</strong> <code>${esc(i.serial)}</code><br><strong>Huella SHA-256:</strong> <code>${esc(i.sha256)}</code></p>`);
});

// ---------- HUELLAS ----------
fill('h-alg', HASHES.map((h) => [h, h]));
on('h-go', 'h-out', async () => {
  const f = $('h-file').files[0];
  const data = f ? new Uint8Array(await f.arrayBuffer()) : utf8($('h-in').value);
  const alg = $('h-alg').value; const key = $('h-key').value;
  let value;
  if (key) {
    if (!/^SHA-(256|384|512)$/.test(alg)) throw new Error('HMAC solo está disponible con SHA-256, SHA-384 o SHA-512');
    value = await hmac(alg, key, data);
  } else value = await hashBytes(alg, data);
  const cmp = $('h-cmp').value.trim().toLowerCase().replace(/[\s:]/g, '');
  const note = `${key ? 'HMAC-' : ''}${esc(alg)} de ${f ? `<code>${esc(f.name)}</code>` : 'el texto'}` +
    (cmp ? (cmp === value ? ' — <span class="ok">✔ coincide</span>' : ' — <span class="err">✘ NO coincide</span>') : '');
  result('h-out', { label: 'Resultado', text: value, note, qr: false });
});

// ---------- HERRAMIENTAS ----------
$('g-len').oninput = () => { $('g-len-v').textContent = $('g-len').value; };
on('g-go', 'g-out', async () => {
  const r = tools.generatePassword(+$('g-len').value, { lower: $('g-lower').checked, upper: $('g-upper').checked, digits: $('g-digits').checked, symbols: $('g-symbols').checked });
  result('g-out', { label: 'Contraseña', text: r.password, qr: false, note: `Fuerza: ~${r.bits} bits (${tools.estimateStrength(r.password).label}).` });
});
on('z-hide', 'z-out', async () => {
  if (!$('z-secret').value) throw new Error('Escribe el mensaje a esconder');
  result('z-out', { label: 'Texto con mensaje oculto (se ve normal)', text: tools.hideInText($('z-cover').value, $('z-secret').value), qr: false,
    note: 'Algunas apps eliminan los caracteres invisibles. Funciona bien en correo, Telegram y la mayoría de chats.' });
});
on('z-reveal', 'z-out', async () => {
  result('z-out', { label: 'Mensaje oculto', text: tools.revealFromText($('z-cover').value), qr: false });
});
on('q-go', 'q-out', async () => { await renderQR($('q-out'), $('q-in').value || ' '); });
fill('e-fmt', Object.keys(tools.ENCODINGS).map((k) => [k, k]));
on('e-enc', 'e-out', async () => result('e-out', { label: 'Codificado', text: tools.ENCODINGS[$('e-fmt').value].enc($('e-in').value), qr: false }));
on('e-dec', 'e-out', async () => {
  try { result('e-out', { label: 'Decodificado', text: tools.ENCODINGS[$('e-fmt').value].dec($('e-in').value), qr: false }); }
  catch { throw new Error('El texto no tiene un formato válido para ' + $('e-fmt').value); }
});
fill('k-alg', Object.keys(tools.CLASSICAL).map((k) => [k, k]));
on('k-enc', 'k-out', async () => result('k-out', { label: 'Resultado', text: tools.CLASSICAL[$('k-alg').value]($('k-in').value, $('k-key').value, false), qr: false }));
on('k-dec', 'k-out', async () => result('k-out', { label: 'Resultado', text: tools.CLASSICAL[$('k-alg').value]($('k-in').value, $('k-key').value, true), qr: false }));

// ---------- arranque ----------
getSodium(); // precarga
renderIdentity();
if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('./sw.js').catch(() => {});
}
