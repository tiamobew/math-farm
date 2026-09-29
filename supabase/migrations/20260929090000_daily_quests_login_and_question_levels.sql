create table if not exists public.player_login_days (
  user_id uuid not null references public.profiles(id) on delete cascade,
  login_date date not null default ((timezone('Asia/Bangkok', now()))::date),
  login_count integer not null default 1 check (login_count > 0),
  first_login_at timestamptz not null default now(),
  last_login_at timestamptz not null default now(),
  primary key (user_id, login_date)
);

alter table public.player_login_days enable row level security;
drop policy if exists login_days_select_own_or_admin on public.player_login_days;
create policy login_days_select_own_or_admin on public.player_login_days
for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_admin()));
revoke all on public.player_login_days from anon;
revoke insert, update, delete on public.player_login_days from authenticated;
grant select on public.player_login_days to authenticated;

create or replace function public.record_daily_login()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_date date := (timezone('Asia/Bangkok', now()))::date;
  v_count integer;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  insert into public.player_login_days(user_id, login_date)
  values (auth.uid(), v_date)
  on conflict (user_id, login_date) do update
    set login_count = public.player_login_days.login_count + 1,
        last_login_at = now()
  returning login_count into v_count;
  return jsonb_build_object('loginDate', v_date, 'loginCount', v_count);
end;
$$;

create or replace function public.get_daily_progress()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with bounds as (
    select (timezone('Asia/Bangkok', now()))::date as d
  ), stats as (
    select
      coalesce(sum(a.score_awarded) filter (where a.correct), 0)::integer as score,
      count(*) filter (where a.correct and q.score <= 1)::integer as easy,
      count(*) filter (where a.correct and q.score between 2 and 3)::integer as medium,
      count(*) filter (where a.correct and q.score >= 4)::integer as hard
    from public.question_attempts a
    join public.questions q on q.id = a.question_id
    cross join bounds b
    where a.user_id = auth.uid()
      and (timezone('Asia/Bangkok', a.answered_at))::date = b.d
  )
  select jsonb_build_object(
    'date', b.d,
    'loggedIn', exists(select 1 from public.player_login_days l where l.user_id = auth.uid() and l.login_date = b.d),
    'loginCount', coalesce((select l.login_count from public.player_login_days l where l.user_id = auth.uid() and l.login_date = b.d), 0),
    'score', s.score, 'easy', s.easy, 'medium', s.medium, 'hard', s.hard
  )
  from bounds b cross join stats s;
$$;

revoke all on function public.record_daily_login() from public, anon;
grant execute on function public.record_daily_login() to authenticated;
revoke all on function public.get_daily_progress() from public, anon;
grant execute on function public.get_daily_progress() to authenticated;

insert into public.questions(id, question, answer, score, coins, subject, sort_order, active)
values
  ('level_easy_1', '9 + 6 = ?', '15', 1, 25, 'คณิตศาสตร์', 101, true),
  ('level_easy_2', '20 - 7 = ?', '13', 1, 25, 'คณิตศาสตร์', 102, true),
  ('level_easy_3', '36 ÷ 6 = ?', '6', 1, 25, 'คณิตศาสตร์', 103, true),
  ('level_medium_1', '12 × 4 = ?', '48', 2, 40, 'คณิตศาสตร์', 201, true),
  ('level_medium_2', '125 - 47 = ?', '78', 2, 40, 'คณิตศาสตร์', 202, true),
  ('level_medium_3', '9 × 8 + 5 = ?', '77', 3, 50, 'คณิตศาสตร์', 203, true),
  ('level_hard_1', '(18 + 6) ÷ 3 = ?', '8', 4, 70, 'คณิตศาสตร์', 301, true),
  ('level_hard_2', '15 × 6 - 25 = ?', '65', 4, 70, 'คณิตศาสตร์', 302, true),
  ('level_hard_3', '3/4 ของ 80 เท่ากับเท่าไร?', '60', 5, 90, 'คณิตศาสตร์', 303, true)
on conflict (id) do update set
  question = excluded.question, answer = excluded.answer, score = excluded.score,
  coins = excluded.coins, subject = excluded.subject, sort_order = excluded.sort_order, active = true;

create or replace function public.feed_pet(p_pet_key text, p_accessory text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.profiles%rowtype;
  v_type text;
  v_index integer;
  v_owned integer;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_pet_key !~ '^(chicken|duck|fish|pig|cow|pug):[0-9]+$' then raise exception 'รหัสสัตว์ไม่ถูกต้อง'; end if;
  if p_accessory not in ('hat', 'bow', 'bag', 'color_pink', 'color_blue', 'color_green', 'color_purple', 'color_gold') then
    raise exception 'ของตกแต่งไม่ถูกต้อง';
  end if;
  v_type := split_part(p_pet_key, ':', 1);
  v_index := split_part(p_pet_key, ':', 2)::integer;
  select * into p from public.profiles where id = auth.uid() for update;
  if not found then raise exception 'ไม่พบผู้เล่น'; end if;
  v_owned := coalesce((p.pets ->> v_type)::integer, 0);
  if v_index < 0 or v_index >= v_owned then raise exception 'ไม่พบสัตว์ตัวนี้'; end if;
  if p.pet_food < 1 then raise exception 'อาหารสัตว์หมดแล้ว'; end if;
  update public.profiles
  set pet_food = pet_food - 1,
      pet_styles = jsonb_set(pet_styles, array[p_pet_key], to_jsonb(p_accessory), true)
  where id = auth.uid() returning * into p;
  return jsonb_build_object('petFood', p.pet_food, 'petStyles', p.pet_styles, 'petKey', p_pet_key, 'accessory', p_accessory);
end;
$$;

revoke all on function public.feed_pet(text, text) from public, anon;
grant execute on function public.feed_pet(text, text) to authenticated;
