// Cifra la app completa con una contraseña para publicarla en una web pública.
// Quien no tenga la contraseña solo descarga datos ilegibles.
//
//   APP_PASSWORD='...' node scripts/protect.mjs
//
// Entrada:  dist-single/index.html (npm run build:single)
// Salida:   dist-protected/ (index.html cifrado + manifest, icono y service worker)
import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { webcrypto as crypto } from 'node:crypto';

const ITER = 1_000_000;
const password = process.env.APP_PASSWORD;
if (!password || password.length < 12) {
  console.error('Falta APP_PASSWORD o tiene menos de 12 caracteres.');
  process.exit(1);
}

const html = await readFile('dist-single/index.html');
const salt = crypto.getRandomValues(new Uint8Array(16));
const iv = crypto.getRandomValues(new Uint8Array(12));
const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveKey']);
const key = await crypto.subtle.deriveKey({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: ITER }, base, { name: 'AES-GCM', length: 256 }, false, ['encrypt']);
const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, html));
const b64 = (b) => Buffer.from(b).toString('base64');

const loader = `<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="theme-color" content="#0f766e">
<title>CIFRA</title>
<link rel="manifest" href="manifest.webmanifest"><link rel="icon" href="icon.svg" type="image/svg+xml">
<style>
:root{--bg:#f6f7f8;--s:#fff;--t:#16191d;--m:#5b6470;--b:#d9dde2;--a:#0f766e;--at:#fff;--e:#b42318}
@media (prefers-color-scheme:dark){:root{--bg:#0f1215;--s:#171b20;--t:#e7eaee;--m:#9aa4b1;--b:#2a3038;--a:#2dd4bf;--at:#04201d;--e:#f97066}}
*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--bg);color:var(--t);font:16px/1.5 system-ui,sans-serif;padding:16px}
form{width:100%;max-width:360px;background:var(--s);border:1px solid var(--b);border-radius:12px;padding:24px}
h1{margin:0 0 4px;font-size:1.4rem}p{color:var(--m);margin:0 0 16px;font-size:.9rem}
input[type=password]{width:100%;padding:12px;font:inherit;color:var(--t);background:var(--bg);border:1px solid var(--b);border-radius:8px}
label.r{display:flex;gap:8px;align-items:center;margin:12px 0;font-size:.9rem;color:var(--m)}
button{width:100%;padding:12px;font:inherit;font-weight:600;border:0;border-radius:8px;background:var(--a);color:var(--at);cursor:pointer}
button:disabled{opacity:.6}#err{color:var(--e);min-height:1.5em;margin:8px 0 0;font-weight:600}
</style></head><body>
<form id="f"><h1>🔐 CIFRA</h1><p>Esta aplicación está protegida. Escribe la contraseña de acceso.</p>
<input id="pw" type="password" autocomplete="current-password" autofocus aria-label="Contraseña">
<label class="r"><input type="checkbox" id="rem"> Recordar en este dispositivo</label>
<button id="go">Entrar</button><p id="err" role="alert"></p></form>
<script>
const D={s:"${b64(salt)}",i:"${b64(iv)}",n:${ITER},c:"${b64(ct)}"};
const u=(s)=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
const K='cifra.acceso.'+D.s;
async function openWith(key){
  const html=new TextDecoder().decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:u(D.i)},key,u(D.c)));
  document.open();document.write(html);document.close();
}
async function fromRemembered(){
  try{const raw=localStorage.getItem(K);if(!raw)return;
    await openWith(await crypto.subtle.importKey('raw',u(raw),'AES-GCM',false,['decrypt']));
  }catch{try{localStorage.removeItem(K)}catch{}}
}
document.getElementById('f').onsubmit=async(e)=>{
  e.preventDefault();const b=document.getElementById('go'),err=document.getElementById('err');
  b.disabled=true;b.textContent='Comprobando…';err.textContent='';
  try{
    const base=await crypto.subtle.importKey('raw',new TextEncoder().encode(document.getElementById('pw').value),'PBKDF2',false,['deriveKey']);
    const key=await crypto.subtle.deriveKey({name:'PBKDF2',hash:'SHA-256',salt:u(D.s),iterations:D.n},base,{name:'AES-GCM',length:256},true,['decrypt']);
    await crypto.subtle.decrypt({name:'AES-GCM',iv:u(D.i)},key,u(D.c));
    if(document.getElementById('rem').checked){try{
      const raw=new Uint8Array(await crypto.subtle.exportKey('raw',key));
      localStorage.setItem(K,btoa(String.fromCharCode(...raw)));}catch{}}
    await openWith(key);
  }catch{err.textContent='Contraseña incorrecta';b.disabled=false;b.textContent='Entrar';}
};
fromRemembered();
</script></body></html>`;

await mkdir('dist-protected', { recursive: true });
await writeFile('dist-protected/index.html', loader);
for (const f of ['manifest.webmanifest', 'icon.svg', 'sw.js']) await copyFile(`public/${f}`, `dist-protected/${f}`);
await writeFile('dist-protected/.nojekyll', '');
console.log(`Listo: dist-protected/index.html (${(loader.length / 1024).toFixed(0)} KB, cifrado)`);
