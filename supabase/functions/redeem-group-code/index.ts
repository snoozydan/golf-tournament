// ============================================================================
//  Edge Function: redeem-group-code
//  Deploy with: supabase functions deploy redeem-group-code --no-verify-jwt
//
//  Trades a 4-char group code for a short-lived JWT whose `group_id` claim
//  unlocks the RLS policy that lets that group write scores.
//
//  Request:  POST /functions/v1/redeem-group-code  { code: "GF2P" }
//  Response: 200 { token, group_id, tournament_id }  |  401 { error }
//
//  The JWT is signed with the project's JWT_SECRET (available automatically
//  inside Supabase edge functions). The public site stores it in sessionStorage
//  and attaches it to every supabase-js call via `global.headers`.
// ============================================================================

import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { create, getNumericDate } from 'https://deno.land/x/djwt@v3.0.1/mod.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const JWT_SECRET   = Deno.env.get('SUPABASE_JWT_SECRET')!;

// Import the raw JWT secret as an HMAC key once at cold-start.
const keyPromise = crypto.subtle.importKey(
  'raw',
  new TextEncoder().encode(JWT_SECRET),
  { name: 'HMAC', hash: 'SHA-256' },
  false,
  ['sign', 'verify'],
);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST')    return json({ error: 'method_not_allowed' }, 405);

  let body: { code?: string };
  try { body = await req.json(); } catch { return json({ error: 'bad_json' }, 400); }

  const code = (body.code ?? '').toUpperCase().trim();
  if (!/^[A-Z0-9]{4}$/.test(code)) return json({ error: 'bad_code' }, 400);

  // Look up the group by code. Using service-role so RLS doesn't apply here.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
  const { data: group, error } = await admin
    .from('groups')
    .select('id, tournament_id, number, tee_time, code')
    .eq('code', code)
    .maybeSingle();

  if (error || !group) return json({ error: 'not_found' }, 401);

  // Mint a 12-hour JWT with role=anon + group_id claim. RLS policy reads this claim.
  const key = await keyPromise;
  const token = await create(
    { alg: 'HS256', typ: 'JWT' },
    {
      role: 'anon',
      group_id: group.id,
      tournament_id: group.tournament_id,
      iat: getNumericDate(0),
      exp: getNumericDate(60 * 60 * 12),
    },
    key,
  );

  return json({ token, group_id: group.id, tournament_id: group.tournament_id });
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
