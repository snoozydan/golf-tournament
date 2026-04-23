-- ============================================================================
--  Seed: 2026 Masters demo tournament at Goose Creek
--  Run after 01_schema.sql. Safe to re-run — wipes + re-inserts the demo data.
-- ============================================================================

begin;

-- Clear anything already there (demo-only; remove for prod)
delete from public.scores;
delete from public.players;
delete from public.groups;
delete from public.tournaments;

-- Tournament ------------------------------------------------------------------
with t as (
  insert into public.tournaments (
    name, course_name, status, live_round, purse, scoring_model,
    course_pars, course_yards, course_hcp, course_hole_names
  ) values (
    '2026 Masters', 'Goose Creek', 'live', 3, 2400, 'hole-strokes',
    ARRAY[4,4,3,5,4,4,3,5,4, 4,3,4,5,4,4,4,3,5]::smallint[],
    ARRAY[412,445,178,524,401,462,188,551,395, 428,165,418,538,432,476,408,195,542]::smallint[],
    ARRAY[7,3,17,1,13,5,15,9,11, 8,18,4,2,6,10,14,16,12]::smallint[],
    ARRAY['Opening','The Arroyo','Short Iron','Eagle Run','Dogleg Right','The Crest','Island','Double Dog','Amen Turn','Back Nine','The Fall','Long Par 4','Reachable','The Grove','Fairway Bunker','Into the Wind','Postage Stamp','Home']
  )
  returning id
)
update public.app_state set live_tournament_id = (select id from t) where id = 1;

-- Groups ---------------------------------------------------------------------
-- Reuse the same tournament_id for all subsequent inserts
do $$
declare tid uuid;
begin
  select id into tid from public.tournaments where name = '2026 Masters' limit 1;

  insert into public.groups (tournament_id, number, tee_time, code) values
    (tid, 1, '8:10 AM', 'GF2P'),
    (tid, 2, '8:22 AM', 'MK7A'),
    (tid, 3, '8:34 AM', 'RB9X'),
    (tid, 4, '8:46 AM', 'QN4H');

  -- Players -----------------------------------------------------------------
  insert into public.players (tournament_id, group_id, name, handicap) values
    (tid, (select id from public.groups where tournament_id=tid and number=1), 'Scott Hitomi',  8),
    (tid, (select id from public.groups where tournament_id=tid and number=1), 'Justin Yun',    14),
    (tid, (select id from public.groups where tournament_id=tid and number=1), 'Joe Park',      18),
    (tid, (select id from public.groups where tournament_id=tid and number=2), 'James Kim',     4),
    (tid, (select id from public.groups where tournament_id=tid and number=2), 'Steve Choi',    12),
    (tid, (select id from public.groups where tournament_id=tid and number=2), 'Mike Kwon',     10),
    (tid, (select id from public.groups where tournament_id=tid and number=3), 'James Choi',    22),
    (tid, (select id from public.groups where tournament_id=tid and number=3), 'Jim Chung',     16),
    (tid, (select id from public.groups where tournament_id=tid and number=3), 'Brian Ko',      20),
    (tid, (select id from public.groups where tournament_id=tid and number=4), 'Sam Baik',      11),
    (tid, (select id from public.groups where tournament_id=tid and number=4), 'Daniel Johung', 7),
    (tid, (select id from public.groups where tournament_id=tid and number=4), 'Tim Yoo',       15);

  -- Scores through hole 12 for the live-round feel ---------------------------
  -- (player_name, hole, strokes)
  insert into public.scores (player_id, hole, strokes)
  select p.id, v.hole, v.strokes
  from (values
    ('Scott Hitomi',  1, 4),('Scott Hitomi',  2, 4),('Scott Hitomi',  3, 2),('Scott Hitomi',  4, 6),('Scott Hitomi',  5, 4),('Scott Hitomi',  6, 4),('Scott Hitomi',  7, 3),('Scott Hitomi',  8, 6),('Scott Hitomi',  9, 3),('Scott Hitomi', 10, 4),('Scott Hitomi', 11, 3),('Scott Hitomi', 12, 5),
    ('Justin Yun',    1, 5),('Justin Yun',    2, 4),('Justin Yun',    3, 4),('Justin Yun',    4, 5),('Justin Yun',    5, 6),('Justin Yun',    6, 4),('Justin Yun',    7, 4),('Justin Yun',    8, 6),('Justin Yun',    9, 4),('Justin Yun',   10, 5),('Justin Yun',   11, 3),('Justin Yun',   12, 4),
    ('Joe Park',      1, 5),('Joe Park',      2, 6),('Joe Park',      3, 4),('Joe Park',      4, 5),('Joe Park',      5, 5),('Joe Park',      6, 5),('Joe Park',      7, 3),('Joe Park',      8, 7),('Joe Park',      9, 5),('Joe Park',     10, 4),('Joe Park',     11, 4),('Joe Park',     12, 5),
    ('James Kim',     1, 4),('James Kim',     2, 3),('James Kim',     3, 3),('James Kim',     4, 4),('James Kim',     5, 4),('James Kim',     6, 4),('James Kim',     7, 2),('James Kim',     8, 5),('James Kim',     9, 4),('James Kim',    10, 4),('James Kim',    11, 3),('James Kim',    12, 3),
    ('Steve Choi',    1, 4),('Steve Choi',    2, 5),('Steve Choi',    3, 3),('Steve Choi',    4, 6),('Steve Choi',    5, 4),('Steve Choi',    6, 4),('Steve Choi',    7, 4),('Steve Choi',    8, 5),('Steve Choi',    9, 4),('Steve Choi',   10, 5),('Steve Choi',   11, 3),('Steve Choi',   12, 4),
    ('Mike Kwon',     1, 5),('Mike Kwon',     2, 4),('Mike Kwon',     3, 3),('Mike Kwon',     4, 6),('Mike Kwon',     5, 4),('Mike Kwon',     6, 5),('Mike Kwon',     7, 3),('Mike Kwon',     8, 5),('Mike Kwon',     9, 5),('Mike Kwon',    10, 4),('Mike Kwon',    11, 4),('Mike Kwon',    12, 4),
    ('James Choi',    1, 6),('James Choi',    2, 5),('James Choi',    3, 4),('James Choi',    4, 7),('James Choi',    5, 5),('James Choi',    6, 6),('James Choi',    7, 4),('James Choi',    8, 7),('James Choi',    9, 5),('James Choi',   10, 5),('James Choi',   11, 4),('James Choi',   12, 6),
    ('Jim Chung',     1, 5),('Jim Chung',     2, 5),('Jim Chung',     3, 3),('Jim Chung',     4, 6),('Jim Chung',     5, 5),('Jim Chung',     6, 4),('Jim Chung',     7, 4),('Jim Chung',     8, 6),('Jim Chung',     9, 4),('Jim Chung',    10, 5),('Jim Chung',    11, 3),('Jim Chung',    12, 5),
    ('Brian Ko',      1, 5),('Brian Ko',      2, 6),('Brian Ko',      3, 4),('Brian Ko',      4, 6),('Brian Ko',      5, 6),('Brian Ko',      6, 5),('Brian Ko',      7, 3),('Brian Ko',      8, 7),('Brian Ko',      9, 5),('Brian Ko',     10, 6),('Brian Ko',     11, 4),('Brian Ko',     12, 5),
    ('Sam Baik',      1, 4),('Sam Baik',      2, 5),('Sam Baik',      3, 2),('Sam Baik',      4, 6),('Sam Baik',      5, 5),('Sam Baik',      6, 4),('Sam Baik',      7, 3),('Sam Baik',      8, 6),('Sam Baik',      9, 4),('Sam Baik',     10, 5),('Sam Baik',     11, 2),('Sam Baik',     12, 5),
    ('Daniel Johung', 1, 5),('Daniel Johung', 2, 4),('Daniel Johung', 3, 3),('Daniel Johung', 4, 5),('Daniel Johung', 5, 5),('Daniel Johung', 6, 4),('Daniel Johung', 7, 3),('Daniel Johung', 8, 6),('Daniel Johung', 9, 3),('Daniel Johung',10, 4),('Daniel Johung',11, 3),('Daniel Johung',12, 5),
    ('Tim Yoo',       1, 5),('Tim Yoo',       2, 5),('Tim Yoo',       3, 3),('Tim Yoo',       4, 5),('Tim Yoo',       5, 5),('Tim Yoo',       6, 6),('Tim Yoo',       7, 3),('Tim Yoo',       8, 6),('Tim Yoo',       9, 5),('Tim Yoo',      10, 4),('Tim Yoo',      11, 5),('Tim Yoo',      12, 4)
  ) as v(name, hole, strokes)
  join public.players p on p.name = v.name and p.tournament_id = tid;
end $$;

commit;
