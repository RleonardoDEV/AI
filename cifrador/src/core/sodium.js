import _sodium from 'libsodium-wrappers-sumo';

let ready;
// Carga libsodium (WebAssembly) una sola vez.
export function getSodium() {
  if (!ready) ready = _sodium.ready.then(() => _sodium);
  return ready;
}
