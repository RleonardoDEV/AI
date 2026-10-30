# CIFRA — aplicación de cifrado

Aplicación web instalable (PWA) que funciona en el **ordenador y en el móvil**. Todo el cifrado ocurre en tu dispositivo: no hay servidor y nada se envía a internet.

## Funciones

| Sección | Qué hace | Inspirado en |
|---|---|---|
| **Texto** | Cifra texto con contraseña. Tres algoritmos: XChaCha20-Poly1305, AES-256-GCM y la Cascada CIFRA (ambos a la vez) | Cryptomator, age |
| **Archivos** | Cifra cualquier archivo en un `.cifra`. El nombre original también queda oculto | VeraCrypt, Picocrypt, AxCrypt |
| **Enlace seguro** | Convierte texto o enlaces en un enlace cifrado. La clave va tras el `#` o se protege con contraseña | PrivateBin, Firefox Send |
| **Conversaciones** | Identidad con claves **post-cuánticas híbridas** (X25519 + ML-KEM-768), contactos con huella, mensajes cifrados y firmados, firmas de texto | Signal (PQXDH), iMessage PQ3, Keybase |
| **OpenPGP** | Generar claves, cifrar, descifrar, firmar y verificar. Compatible con GnuPG, Kleopatra, Thunderbird, OpenKeychain y Proton | Kleopatra, OpenKeychain |
| **Certificados** | Certificados X.509 autofirmados, CA propia + certificados de servidor, solicitudes CSR, inspector de certificados | XCA, OpenSSL |
| **Huellas** | SHA-2, SHA-3, BLAKE2b, HMAC. Comprueba descargas comparando el hash | HashCalc, 7-Zip |
| **Herramientas** | Generador de contraseñas, mensajes ocultos en texto (esteganografía), QR, Base64/Hex/URL, cifrados clásicos educativos | Bitwarden, CyberChef |

En **Cifrado CIFRA**, dentro de la app, se explica el diseño y por qué no se inventa un algoritmo desde cero (resumen abajo).

## Usarla

```bash
cd cifrador
npm install
npm run dev          # abre http://localhost:5173
npm test             # pruebas automáticas
npm run build        # carpeta dist/ para publicar (GitHub Pages, Netlify…)
npm run build:single # un solo archivo dist-single/index.html que funciona sin servidor
```

**Instalar en el móvil u ordenador:** publica `dist/` en cualquier hosting con HTTPS (por ejemplo, GitHub Pages). Abre la dirección en Chrome, Edge o Safari y elige **"Instalar app"** o **"Añadir a pantalla de inicio"**. Después funciona sin conexión.

Para que los **enlaces seguros** funcionen con otras personas, la app tiene que estar publicada en una dirección pública. Los enlaces se abren en esa misma dirección.

## Diseño criptográfico

- **Contraseñas:** Argon2id (64 MiB, 3 pasadas) o PBKDF2-SHA256 (600 000 iteraciones).
- **Cifrado:** XChaCha20-Poly1305 (libsodium) y AES-256-GCM (WebCrypto). Siempre autenticado y con la cabecera como datos asociados (AAD).
- **Cascada CIFRA:** Argon2id → 64 bytes → dos claves independientes → AES-256-GCM dentro de XChaCha20-Poly1305.
- **Clave pública:** X25519 ⊕ ML-KEM-768 (FIPS 203), combinadas con BLAKE2b. Firma Ed25519 que incluye la huella del destinatario.
- **Formato:** `cifra1.<alg>.<parámetros>.<sal>.<nonce>.<datos>`, en Base64URL.
- **Librerías:** libsodium, @noble/post-quantum, @noble/hashes, OpenPGP.js, @peculiar/x509 (todas de código abierto y muy usadas).

### ¿Por qué no un algoritmo nuevo?

Un algoritmo inventado no ha pasado años de ataques públicos, y casi siempre es más débil que AES o ChaCha20. CIFRA mejora la seguridad de otra forma: **combina algoritmos probados para que haya que romper varios a la vez**. Usa dos familias de cifrado distintas en cascada y un acuerdo de clave clásico más otro post-cuántico.

> ⚠ Este código no ha pasado una auditoría de seguridad independiente. Para información de vida o muerte, usa herramientas auditadas (Signal, VeraCrypt, GnuPG).
