// Builds the admin web page into public/, which the Worker serves as static
// assets: the bundled app, styles, fonts (shared with the iPad app) and the
// security headers.
import { build } from "esbuild";
import { cpSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const out = join(root, "public");
rmSync(out, { recursive: true, force: true });
mkdirSync(join(out, "fonts"), { recursive: true });

await build({
  entryPoints: [join(root, "web/src/main.tsx")],
  bundle: true,
  format: "esm",
  target: "es2022",
  minify: true,
  jsx: "automatic",
  jsxImportSource: "preact",
  outfile: join(out, "app.js"),
  logLevel: "warning",
});

for (const file of ["index.html", "styles.css", "_headers", "robots.txt"]) {
  cpSync(join(root, "web", file), join(out, file));
}
const fonts = join(root, "../App/Fonts");
for (const font of [
  "PlayfairDisplay-SemiBold.ttf",
  "PlayfairDisplay-Bold.ttf",
  "EBGaramond-Regular.ttf",
  "EBGaramond-Italic.ttf",
  "EBGaramond-Medium.ttf",
  "EBGaramond-SemiBold.ttf",
]) {
  cpSync(join(fonts, font), join(out, "fonts", font));
}
console.log("Built the web page into public/");
