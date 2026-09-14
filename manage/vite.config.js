import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { handleApi, ASSETS_DIR } from './server/api.js';

// Mounts the asset API inside the Vite dev server so `npm run dev` is a single process.
const assetApi = {
  name: 'asset-api',
  configureServer(server) {
    server.config.logger.info(`  Editing JSON files in ${ASSETS_DIR}`);
    server.middlewares.use(async (req, res, next) => {
      if (!(await handleApi(req, res))) next();
    });
  },
};

export default defineConfig({
  plugins: [react(), assetApi],
  server: { host: '127.0.0.1', port: 5173 },
});
