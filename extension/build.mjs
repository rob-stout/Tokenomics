import * as esbuild from 'esbuild';
import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';

const watch = process.argv.includes('--watch');
// Safari Web Extensions ship as a native-app resource bundle rather than a
// Chrome Web Store upload, and Safari has two hard requirements Chrome
// doesn't: no `type: module` service worker, and no Chrome-only `key` field
// in the manifest (see the manifest transform below). Everything else — the
// bundling of content scripts, popup, and options — is identical, so this
// mode reuses the exact same esbuild steps with one output dir and one extra
// background-script context.
const safari = process.argv.includes('--safari');
const outdir = safari ? 'dist-safari' : 'dist';

await rm(outdir, { recursive: true, force: true });
await mkdir(outdir, { recursive: true });

const shared = {
  bundle: true,
  outdir,
  target: 'chrome120',
  jsx: 'automatic',
  jsxImportSource: 'preact',
  logLevel: 'info',
  sourcemap: watch ? 'inline' : false,
  minify: !watch,
};

// SW + popup ship as ES modules (the SW manifest declares `type: module`).
// On Safari, background.js is bundled separately below (classic script) —
// omitted here so it isn't double-built.
const moduleCtx = await esbuild.context({
  ...shared,
  entryPoints: {
    ...(safari ? {} : { background: 'src/background.ts' }),
    'popup/popup': 'src/popup/popup.tsx',
    'options/options': 'src/options/options.tsx',
  },
  format: 'esm',
});

// Safari doesn't support `background.service_worker.type: "module"` — bundle
// the same background.ts entry point as a classic IIFE instead, matching how
// content scripts are already built below. No source changes needed:
// esbuild's `format` option only controls the output wrapper, not what
// import syntax the input may use.
const backgroundCtx = safari
  ? await esbuild.context({
      ...shared,
      entryPoints: { background: 'src/background.ts' },
      format: 'iife',
    })
  : null;

// Content scripts must be classic scripts — Chrome rejects ESM in this slot.
const contentCtx = await esbuild.context({
  ...shared,
  entryPoints: {
    'content/chatgpt-watch': 'src/content/chatgpt-watch.ts',
    'content/gemini-main': 'src/content/gemini-main.ts',
    'content/gemini-watch': 'src/content/gemini-watch.ts',
    'content/elevenlabs-grab': 'src/content/elevenlabs-grab.ts',
    'content/leonardo-main': 'src/content/leonardo-main.ts',
    'content/leonardo-watch': 'src/content/leonardo-watch.ts',
  },
  format: 'iife',
});

await Promise.all([
  moduleCtx.rebuild(),
  contentCtx.rebuild(),
  ...(backgroundCtx ? [backgroundCtx.rebuild()] : []),
]);

if (safari) {
  // Safari-only manifest transform: drop the Chrome-only `key` (extension-ID
  // pinning) and `background.type` (module service workers unsupported —
  // background.js above is bundled as a classic script instead). Everything
  // else in the manifest is identical, including `world: "MAIN"` content
  // script entries and `options_ui.open_in_tab` — Safari's converter flags
  // both as unsupported keys but ignores them harmlessly rather than
  // erroring, so they're kept as-is for Chrome/Safari parity.
  const manifest = JSON.parse(await readFile('src/manifest.json', 'utf8'));
  delete manifest.key;
  delete manifest.background.type;
  await writeFile(`${outdir}/manifest.json`, `${JSON.stringify(manifest, null, 2)}\n`);
} else {
  await cp('src/manifest.json', `${outdir}/manifest.json`);
}

await cp('src/popup/index.html', `${outdir}/popup/index.html`);
await cp('src/popup/popup.css', `${outdir}/popup/popup.css`);
await cp('src/popup/tokens.css', `${outdir}/popup/tokens.css`);
await mkdir(`${outdir}/options`, { recursive: true });
await cp('src/options/index.html', `${outdir}/options/index.html`);
// options.css @imports tokens.css relatively, so tokens.css must sit next to it.
await cp('src/popup/tokens.css', `${outdir}/options/tokens.css`);
// options.css is bundled by esbuild as CSS (since it's a sibling to the TSX
// entrypoint); the browser also needs the raw file for the HTML <link>.
await cp('src/options/options.css', `${outdir}/options/options.css`);
if (existsSync('src/icons')) {
  await cp('src/icons', `${outdir}/icons`, { recursive: true });
}

if (watch) {
  console.log('Watching for changes…');
  await Promise.all([moduleCtx.watch(), contentCtx.watch(), ...(backgroundCtx ? [backgroundCtx.watch()] : [])]);
} else {
  await Promise.all([moduleCtx.dispose(), contentCtx.dispose(), ...(backgroundCtx ? [backgroundCtx.dispose()] : [])]);
  console.log(`Build complete → ${outdir}/`);
}
