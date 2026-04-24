// Reads index.html + admin.html, injects Supabase credentials as window globals,
// then writes everything to /public. Runs on every Vercel build.
//
// Required env vars (set in Vercel dashboard → Settings → Environment Variables):
//   NEXT_PUBLIC_SUPABASE_URL
//   NEXT_PUBLIC_SUPABASE_ANON_KEY

const fs   = require('fs');
const path = require('path');

const URL  = process.env.NEXT_PUBLIC_SUPABASE_URL        || '';
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY   || '';

if (!URL || !ANON) {
  console.warn('⚠️  SUPABASE env vars not set — deploying in demo mode (no live data).');
  console.warn('   Add NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in Vercel.');
}

const outDir    = path.join(__dirname, '..', 'public');
const outWebDir = path.join(outDir, 'web');
fs.mkdirSync(outDir,    { recursive: true });
fs.mkdirSync(outWebDir, { recursive: true });

// Inject credentials so window.golfData (data.js) can pick them up at runtime.
// When env vars are absent the globals are empty strings and the app falls back
// to demo data automatically.
const stamp = `<script>window.__SUPABASE_URL__=${JSON.stringify(URL)};window.__SUPABASE_ANON_KEY__=${JSON.stringify(ANON)};</script>`;

for (const file of ['index.html', 'admin.html']) {
  const src = fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
  const out = src.replace(/<head>/i, `<head>${stamp}`);
  fs.writeFileSync(path.join(outDir, file), out);
  console.log('✓ built', file);
}

// Copy web/data.js → public/web/data.js so it's reachable at /web/data.js
const dataJs = fs.readFileSync(path.join(__dirname, '..', 'web', 'data.js'), 'utf8');
fs.writeFileSync(path.join(outWebDir, 'data.js'), dataJs);
console.log('✓ built web/data.js');
