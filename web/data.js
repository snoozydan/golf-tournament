// ============================================================================
//  data.js — drop-in data layer for index.html + admin.html
//  Replaces the in-memory demo state. Same shape the React components already
//  consume: { tournament, groups[], players[], scoresByPlayer{[pid]:[18]} }.
//
//  Usage (in your HTML <head>):
//    <script type="module" src="./data.js"></script>
//
//  Then anywhere in the app:
//    const { data, subscribe, writeScore, signInWithCode, signOut, isAdmin } = window.golfData;
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

// ---------- Config (replace at deploy) -------------------------------------
const SUPABASE_URL      = window.__SUPABASE_URL__      || 'https://YOUR-PROJECT.supabase.co';
const SUPABASE_ANON_KEY = window.__SUPABASE_ANON_KEY__ || 'YOUR-ANON-KEY';

// ---------- Client ----------------------------------------------------------
// A mutable headers object so we can swap in the group-code JWT after sign-in
// without rebuilding the client.
const authHeaders = {};
let client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: { headers: authHeaders },
  realtime: { params: { eventsPerSecond: 20 } },
});

function setAuthToken(token) {
  if (token) {
    authHeaders['Authorization'] = `Bearer ${token}`;
    sessionStorage.setItem('golf_token', token);
  } else {
    delete authHeaders['Authorization'];
    sessionStorage.removeItem('golf_token');
  }
  // Re-auth the realtime socket with the new token
  client.realtime.setAuth(token || SUPABASE_ANON_KEY);
}

// Restore session on load
const savedToken = sessionStorage.getItem('golf_token');
if (savedToken) setAuthToken(savedToken);

// ---------- In-memory cache --------------------------------------------------
const state = {
  tournament: null,
  groups: [],
  players: [],
  scoresByPlayer: {},     // { playerId: [null|number × 18] }
  signedInGroupId: null,
  signedInPlayerId: null,
  isAdmin: false,
};
const listeners = new Set();
const notify = () => listeners.forEach((fn) => { try { fn(state); } catch (e) { console.error(e); } });

// ---------- Fetch full snapshot ---------------------------------------------
async function loadAll() {
  // 1. Find the live tournament
  const { data: appState } = await client.from('app_state').select('live_tournament_id').maybeSingle();
  const tid = appState?.live_tournament_id;
  if (!tid) { state.tournament = null; notify(); return; }

  const [{ data: t }, { data: groups }, { data: players }, { data: scores }] = await Promise.all([
    client.from('tournaments').select('*').eq('id', tid).single(),
    client.from('groups').select('*').eq('tournament_id', tid).order('number'),
    client.from('players').select('*').eq('tournament_id', tid).order('name'),
    client.from('scores').select('player_id, hole, strokes')
      .in('player_id', (await client.from('players').select('id').eq('tournament_id', tid)).data?.map((r) => r.id) ?? []),
  ]);

  state.tournament = t;
  state.groups = groups ?? [];
  state.players = players ?? [];
  state.scoresByPlayer = {};
  for (const p of state.players) state.scoresByPlayer[p.id] = Array(18).fill(null);
  for (const s of scores ?? []) {
    const row = state.scoresByPlayer[s.player_id];
    if (row) row[s.hole - 1] = s.strokes;
  }
  notify();
}

// ---------- Realtime subscription -------------------------------------------
function wireRealtime() {
  client
    .channel('golf-all')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'scores' }, (payload) => {
      const row = payload.new || payload.old;
      if (!row) return;
      const list = state.scoresByPlayer[row.player_id];
      if (!list) return;
      if (payload.eventType === 'DELETE') list[row.hole - 1] = null;
      else list[row.hole - 1] = row.strokes;
      notify();
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'players' },    () => loadAll())
    .on('postgres_changes', { event: '*', schema: 'public', table: 'groups' },     () => loadAll())
    .on('postgres_changes', { event: '*', schema: 'public', table: 'tournaments' }, () => loadAll())
    .on('postgres_changes', { event: '*', schema: 'public', table: 'app_state' },   () => loadAll())
    .subscribe();
}

// ---------- Writes (scoped by RLS) ------------------------------------------
async function writeScore(playerId, hole, strokes) {
  // Optimistic update
  const list = state.scoresByPlayer[playerId];
  const prev = list ? list[hole - 1] : null;
  if (list) { list[hole - 1] = strokes; notify(); }

  const payload = { player_id: playerId, hole, strokes, scored_by_group_id: state.signedInGroupId };
  const { error } = strokes == null
    ? await client.from('scores').delete().eq('player_id', playerId).eq('hole', hole)
    : await client.from('scores').upsert(payload, { onConflict: 'player_id,hole' });

  if (error) {
    // Roll back
    if (list) { list[hole - 1] = prev; notify(); }
    throw error;
  }
}

// ---------- Group-code sign-in ----------------------------------------------
async function signInWithCode(code) {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/redeem-group-code`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'apikey': SUPABASE_ANON_KEY },
    body: JSON.stringify({ code: (code || '').toUpperCase().trim() }),
  });
  if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || 'sign_in_failed');
  const { token, group_id } = await res.json();
  setAuthToken(token);
  state.signedInGroupId = group_id;
  state.isAdmin = false;
  sessionStorage.setItem('golf_group_id', group_id);
  notify();
  return group_id;
}

function signOut() {
  setAuthToken(null);
  state.signedInGroupId = null;
  state.signedInPlayerId = null;
  state.isAdmin = false;
  sessionStorage.removeItem('golf_group_id');
  sessionStorage.removeItem('golf_player_id');
  notify();
}

function setSignedInPlayer(playerId) {
  state.signedInPlayerId = playerId;
  if (playerId) sessionStorage.setItem('golf_player_id', playerId);
  else sessionStorage.removeItem('golf_player_id');
  notify();
}

// ---------- Admin sign-in (Supabase Auth email+password) --------------------
// Admin logs in with a real Supabase Auth user whose JWT carries `role=admin`.
// Grant this in Dashboard → Authentication → Users → Raw User Meta Data:
//     { "role": "admin" }
async function signInAdmin(email, password) {
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error) throw error;
  const token = data.session?.access_token;
  setAuthToken(token);
  state.isAdmin = true;
  notify();
}

// Restore on reload
state.signedInGroupId   = sessionStorage.getItem('golf_group_id');
state.signedInPlayerId  = sessionStorage.getItem('golf_player_id');

// ---------- Public API ------------------------------------------------------
window.golfData = {
  data: state,
  subscribe: (fn) => { listeners.add(fn); fn(state); return () => listeners.delete(fn); },
  loadAll,
  writeScore,
  signInWithCode,
  setSignedInPlayer,
  signOut,
  signInAdmin,
  client, // escape hatch for admin dashboard CRUD
};

// Boot
loadAll().then(wireRealtime).catch((e) => console.error('Golf data boot failed:', e));
