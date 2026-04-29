import { defineConfig } from "vite";
import path from "node:path";
import fs from "node:fs";

// Serve the shared `assets/cards/` directory at `/cards/*` so the existing
// runtime paths in `src/main.js` keep working after the monorepo migration.
const assetsCardsDir = path.resolve(__dirname, "../../assets/cards");

function serveSharedCards() {
  return {
    name: "carddex-shared-cards",
    configureServer(server) {
      server.middlewares.use("/cards", (req, res, next) => {
        const url = decodeURIComponent((req.url ?? "/").split("?")[0]);
        const filePath = path.join(assetsCardsDir, url);
        if (!filePath.startsWith(assetsCardsDir)) {
          res.statusCode = 403;
          return res.end("Forbidden");
        }
        fs.stat(filePath, (err, stat) => {
          if (err || !stat.isFile()) return next();
          const ext = path.extname(filePath).toLowerCase();
          const types = {
            ".json": "application/json",
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".webp": "image/webp",
          };
          res.setHeader("Content-Type", types[ext] ?? "application/octet-stream");
          fs.createReadStream(filePath).pipe(res);
        });
      });
    },
  };
}

export default defineConfig({
  plugins: [serveSharedCards()],
  server: { host: "0.0.0.0" },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
