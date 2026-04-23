-- ============================================================================
--  Golf Tournament — Supabase Schema
--  Run this in the Supabase SQL editor (or `supabase db push`) on a fresh project.
--  Requires: Postgres 15+ (Supabase default).
-- ============================================================================

-- ---------- Extensions ----------
create extension if not exists "pgcrypto";  -- for gen_random_uuid()

-- ============================================================================
--  CORE TABLES
-- ============================================================================

-- Tournaments ----------------------------------------------------------------
create table public.tournaments (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  course_name     text not null,
  status          text not null check (status in ('upcoming','live','completed')) default 'upcoming',
  live_round      smallint not null default 0,
  purse           integer not null default 0,
  scoring_model   text not null check (scoring_model in ('hole-strokes','starting-handicap')) default 'hole-strokes',
  -- Course layout lives on the tournament so historical rounds keep their own layout:
  course_pars     smallint[] not null check (array_length(course_pars, 1) = 18),
  course_yards    smallint[] not null check (array_length(course_yards, 1) = 18),
  course_hcp      smallint[] not null check (array_length(course_hcp, 1) = 18),
  course_hole_names text[]   not null check (array_length(course_hole_names, 1) = 18),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Exactly one tournament can be flagged as the "public live" one at a time.
-- Admin toggles this from the dashboard.
create table public.app_state (
  id              smallint primary key default 1,
  live_tournament_id uuid references public.tournaments(id) on delete set null,
  updated_at      timestamptz not null default now(),
  constraint app_state_singleton check (id = 1)
);
insert into public.app_state (id) values (1) on conflict do nothing;

-- Groups ---------------------------------------------------------------------
create table public.groups (
  id              uuid primary key default gen_random_uuid(),
  tournament_id   uuid not null references public.tournaments(id) on delete cascade,
  number          smallint not null,                          -- display-only (Group 1, Group 2...)
  tee_time        text,                                        -- freeform ("8:10 AM")
  code            text not null,                               -- 4-char scorer code (uppercase)
  created_at      timestamptz not null default now(),
  unique (tournament_id, number),
  unique (tournament_id, code)                                 -- no dupes per tournament
);
create index groups_tournament_idx on public.groups (tournament_id);

-- Players --------------------------------------------------------------------
create table public.players (
  id              uuid primary key default gen_random_uuid(),
  tournament_id   uuid not null references public.tournaments(id) on delete cascade,
  group_id        uuid references public.groups(id) on delete set null,
  name            text not null,
  handicap        smallint not null default 0,
  winnings        integer not null default 0,
  created_at      timestamptz not null default now()
);
create index players_tournament_idx on public.players (tournament_id);
create index players_group_idx      on public.players (group_id);

-- Scores ---------------------------------------------------------------------
-- One row per (player, hole). Upsert on conflict for idempotent score entry.
create table public.scores (
  player_id       uuid not null references public.players(id) on delete cascade,
  hole            smallint not null check (hole between 1 and 18),
  strokes         smallint check (strokes >= 1 and strokes <= 20),
  scored_by_group_id uuid references public.groups(id) on delete set null,   -- who entered it
  entered_at      timestamptz not null default now(),
  primary key (player_id, hole)
);
create index scores_player_idx on public.scores (player_id);

-- ============================================================================
--  TRIGGERS
-- ============================================================================

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end; $$;

create trigger tournaments_touch
  before update on public.tournaments
  for each row execute function public.touch_updated_at();

-- ============================================================================
--  VIEWS — leaderboard math in the DB so the client stays dumb
-- ============================================================================

-- Per-player totals with par-thru and gross-relative-to-par
create or replace view public.v_player_totals as
select
  p.id                 as player_id,
  p.tournament_id,
  p.group_id,
  p.name,
  p.handicap,
  count(s.hole) filter (where s.strokes is not null)          as holes_played,
  coalesce(sum(s.strokes), 0)::int                             as gross,
  -- Par for only the holes actually played (so partial rounds read correctly)
  coalesce(
    sum(t.course_pars[s.hole]) filter (where s.strokes is not null),
    0
  )::int                                                       as par_played
from public.players p
join public.tournaments t on t.id = p.tournament_id
left join public.scores s on s.player_id = p.id
group by p.id, p.tournament_id, p.group_id, p.name, p.handicap, t.course_pars;

-- Convenience leaderboard view (net + gross relative, sorted client-side if you want ties)
create or replace view public.v_leaderboard as
select
  pt.*,
  (pt.gross - pt.par_played)                                   as gross_rel,
  (pt.gross - pt.par_played)
    - round(pt.handicap * (pt.holes_played::numeric / 18))     as net_rel
from public.v_player_totals pt;

-- ============================================================================
--  REALTIME — subscribe to all score + player + group changes
-- ============================================================================

alter publication supabase_realtime add table public.scores;
alter publication supabase_realtime add table public.players;
alter publication supabase_realtime add table public.groups;
alter publication supabase_realtime add table public.tournaments;
alter publication supabase_realtime add table public.app_state;

-- ============================================================================
--  ROW-LEVEL SECURITY
--  Model:
--    * Public site uses anon key. Reads: anyone. Writes: only via group code,
--      and only to scores inside that group.
--    * Admin site uses service_role key (server-side only) OR a Supabase Auth
--      session whose JWT claim `role = admin`. Admin can do anything.
--
--  The trick for "group code unlocks score writes" without Auth:
--    Postgres session variable `request.jwt.claims.group_id` is set by a
--    lightweight edge function that validates the 4-char code and mints a JWT
--    with that claim. No passwords, no user table.
-- ============================================================================

alter table public.tournaments enable row level security;
alter table public.groups      enable row level security;
alter table public.players     enable row level security;
alter table public.scores      enable row level security;
alter table public.app_state   enable row level security;

-- ---------- Helpers ----------
-- Current signed-in group (uuid) from JWT, if any
create or replace function public.current_group_id()
returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'group_id','')::uuid;
$$;

-- Is the current request an admin? (either service_role, or JWT role=admin)
create or replace function public.is_admin()
returns boolean language sql stable as $$
  select
    current_setting('request.jwt.claims', true)::json->>'role' = 'admin'
    or current_user = 'service_role';
$$;

-- ---------- Policies ----------

-- Tournaments: public read, admin write
create policy "tournaments_read" on public.tournaments
  for select using (true);
create policy "tournaments_write" on public.tournaments
  for all using (public.is_admin()) with check (public.is_admin());

-- Groups: public read (so sign-in can look up by code), admin write
create policy "groups_read" on public.groups
  for select using (true);
create policy "groups_write" on public.groups
  for all using (public.is_admin()) with check (public.is_admin());

-- Players: public read, admin write
create policy "players_read" on public.players
  for select using (true);
create policy "players_write" on public.players
  for all using (public.is_admin()) with check (public.is_admin());

-- Scores:
--   * Public read.
--   * Insert/update/delete only if the signed-in group owns the player being scored,
--     OR the request is admin.
create policy "scores_read" on public.scores
  for select using (true);

create policy "scores_write" on public.scores
  for all
  using (
    public.is_admin()
    or exists (
      select 1 from public.players p
      where p.id = scores.player_id
        and p.group_id = public.current_group_id()
    )
  )
  with check (
    public.is_admin()
    or exists (
      select 1 from public.players p
      where p.id = scores.player_id
        and p.group_id = public.current_group_id()
    )
  );

-- App state: public read, admin write
create policy "app_state_read" on public.app_state
  for select using (true);
create policy "app_state_write" on public.app_state
  for all using (public.is_admin()) with check (public.is_admin());
