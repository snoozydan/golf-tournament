// Reads index.html + admin.html, replaces Supabase placeholders with env vars,
// writes the result to /public. Runs on every Vercel build.
//
//   YOUR-PROJECT.supabase.co        → process.env.NEXT_PUBLIC_SUPABASE_URL
//   YOUR-ANON-KEY                    → process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

const fs = require('fs');
const path = require('path');

const URL  = process.env.NEXT_PUBLIC_SUPABASE_URL;
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if (!URL || !ANON) { console.error('Missing SUPABASE env vars'); process.exit(1); }

const outDir = path.join(__dirname, '..', 'public');
fs.mkdirSync(outDir, { recursive: true });

const stamp = `<script>window.__SUPABASE_URL__=${JSON.stringify(URL)};window.__SUPABASE_ANON_KEY__=${JSON.stringify(ANON)};</script>`;

for (const file of ['index.html', 'admin.html', 'data.js']) {
  const src  = fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
  // Inject the <script> right after <head>; harmless no-op for data.js (it reads window globals).
  const out  = file.endsWith('.html') ? src.replace(/<head>/i, `<head>${stamp}`) : src;
  fs.writeFileSync(path.join(outDir, file), out);
  console.log('✓ built', file);
}
