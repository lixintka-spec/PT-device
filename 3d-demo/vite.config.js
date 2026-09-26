import { defineConfig } from 'vite';

export default defineConfig({
  // three.js alone is ~500 kB minified; that's expected for this demo.
  build: { chunkSizeWarningLimit: 800 },
});
