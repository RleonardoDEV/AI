import { defineConfig } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

// `npm run build`         → carpeta dist/ lista para publicar (PWA instalable).
// `npm run build:single`  → un único archivo HTML con todo dentro (funciona sin servidor).
export default defineConfig(({ mode }) => ({
  base: './',
  build: {
    target: 'es2022',
    outDir: mode === 'single' ? 'dist-single' : 'dist',
    chunkSizeWarningLimit: 4000,
  },
  plugins: mode === 'single' ? [viteSingleFile()] : [],
}));
