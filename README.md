# Golf Tournament Website

Mobile-first tournament site with a live leaderboard, group-code scoring, and an organizer admin console.

## What's in this repo

```
.
├── index.html        ← Public site + player score entry (mobile web)
├── admin.html        ← Organizer console (tournaments, players, groups, course, scores)
├── README.md         ← This file
├── vercel.json       ← Vercel deploy config (zero-build static)
├── package.json      ← Scripts for local dev + env injection
├── .env.example      ← Copy to .env.local and fill with your Supabase keys
├── scripts/
│   └── inject-env.js ← Bakes SUPABASE_URL / ANON_KEY into HTML at build time
├── web/
│   └── data.js       ← Drop-in data layer (Supabase client + CRUD + realtime)
└── supabase/
    ├── 01_schema.sql           ← Tables, RLS, realtime
    ├── 02_seed.sql             ← Demo tournament data (optional)
    └── functions/
        └── redeem-group-code/  ← Edge function: 4-char code → JWT
            └── index.ts
```

## Quick deploy (static, no backend yet)

The HTML files are fully self-contained with demo data — you can deploy as-is for a preview:

1. Push this repo to GitHub.
2. Import into Vercel (https://vercel.com/new). No framework, no build command.
3. Done. `yourdomain.vercel.app` = public site, `yourdomain.vercel.app/admin.html` = admin.

Demo sign-in codes (baked into the HTML):
- Group codes: `GF2P`, `MK7A`, `RB9X`, `QN4H`
- Admin code: `ADMIN`

## Wiring to Supabase (real backend)

See `supabase/` folder and Claude Code instructions in this README — follow the numbered steps below or hand the whole repo to Claude Code.

### 1. Create a Supabase project
1. https://supabase.com/dashboard → New project
2. Copy the Project URL and `anon` public API key into `.env.local` (copy from `.env.example`).

### 2. Run migrations
In the Supabase SQL editor:
1. Run `supabase/01_schema.sql` (tables + RLS + realtime).
2. Optionally run `supabase/02_seed.sql` (the 2026 Masters demo field).

### 3. Deploy the edge function
```bash
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase functions deploy redeem-group-code
```

### 4. Wire the HTML
Two options:

**Option A (fastest) — include `web/data.js` directly:**
Add to the `<head>` of `index.html` and `admin.html`:
```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script>
  window.SUPABASE_URL = 'https://YOUR_PROJECT.supabase.co';
  window.SUPABASE_ANON_KEY = 'YOUR_ANON_KEY';
</script>
<script src="/web/data.js"></script>
```
Then replace the hard-coded `PLAYERS_SEED` and `GROUPS` objects with `await window.dataLayer.loadTournament()`. See `web/data.js` for the full API.

**Option B (production) — build-time injection:**
```bash
npm install
npm run build   # runs scripts/inject-env.js
```
This injects env vars into the HTML at build time so nothing sensitive is in the repo.

### 5. Deploy to Vercel
```bash
git push
```
Vercel auto-deploys on push. Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` in the Vercel project settings (Environment Variables).

## Data model

- `tournaments` — id, name, course, status, round, purse, scoring_model
- `courses` — pars[18], yards[18], hcp_index[18], hole_names[18]
- `players` — id, name, group_id, hcp, tournament_id
- `groups` — id, tee_time, **code** (4-char, shared)
- `scores` — player_id, hole, strokes, posted_at

Group codes are the auth primitive. Any player in a group can use the code to post scores for everyone in the foursome. Admin uses a separate login.

## Local development

```bash
# No build step needed; just serve the static files.
npx serve .
# or: python3 -m http.server 8000
```

Open http://localhost:3000 for the public site, /admin.html for the admin.

## Handoff to Claude Code

If you're using Claude Code: open this folder and tell it
> "Set up the repo per README.md, then wire index.html and admin.html to use web/data.js and Supabase."

All the schema, RLS, and wiring logic it needs is in the `supabase/` and `web/` folders.
