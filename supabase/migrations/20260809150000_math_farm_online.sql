create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.app_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);
revoke all on private.app_settings from public, anon, authenticated;

insert into private.app_settings(key, value)
values ('registration_code', '1234')
on conflict (key) do nothing;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  full_name text not null default '',
  class_name text not null default '',
  student_no text not null default '',
  color text not null default '#4a90ff' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  character_name text not null default 'น้องคณิต',
  role text not null default 'student' check (role in ('student', 'admin')),
  points bigint not null default 0 check (points >= 0),
  coins bigint not null default 0 check (coins >= 0),
  pets jsonb not null default '{}'::jsonb check (jsonb_typeof(pets) = 'object'),
  decor jsonb not null default '{}'::jsonb check (jsonb_typeof(decor) = 'object'),
  farm_state jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists profiles_username_lower_uidx on public.profiles (lower(username));
create index if not exists profiles_points_idx on public.profiles (points desc);

create table if not exists public.missions (
  id text primary key,
  icon text not null default '📘',
  title text not null check (length(title) between 1 and 300),
  points integer not null default 10 check (points between 0 and 100000),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.questions (
  id text primary key,
  question text not null check (length(question) between 1 and 2000),
  answer text not null check (length(answer) between 1 and 500),
  coins integer not null default 25 check (coins between 0 and 100000),
  subject text not null default 'คณิตศาสตร์',
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shop_items (
  type text not null check (type in ('pets', 'decor')),
  id text not null,
  name text not null,
  emoji text not null default '🎁',
  price integer not null check (price between 0 and 100000000),
  active boolean not null default true,
  sort_order integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (type, id)
);

create table if not exists public.mission_completions (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  mission_id text not null references public.missions(id) on delete restrict,
  points_awarded integer not null check (points_awarded >= 0),
  completed_on date not null default ((timezone('Asia/Bangkok', now()))::date),
  completed_at timestamptz not null default now(),
  evidence_data_url text check (evidence_data_url is null or length(evidence_data_url) <= 1000000),
  unique (user_id, mission_id, completed_on)
);
create index if not exists mission_completions_user_id_idx on public.mission_completions(user_id);
create index if not exists mission_completions_mission_id_idx on public.mission_completions(mission_id);
create index if not exists mission_completions_completed_at_idx on public.mission_completions(completed_at desc);

create table if not exists public.question_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  question_id text not null references public.questions(id) on delete restrict,
  submitted_answer text not null,
  correct boolean not null,
  reward integer not null default 0 check (reward >= 0),
  answered_at timestamptz not null default now()
);
create index if not exists question_attempts_user_id_idx on public.question_attempts(user_id);
create index if not exists question_attempts_question_id_idx on public.question_attempts(question_id);

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;
revoke all on function private.is_admin() from public, anon, authenticated;

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at before update on public.profiles
for each row execute function private.touch_updated_at();
drop trigger if exists missions_touch_updated_at on public.missions;
create trigger missions_touch_updated_at before update on public.missions
for each row execute function private.touch_updated_at();
drop trigger if exists questions_touch_updated_at on public.questions;
create trigger questions_touch_updated_at before update on public.questions
for each row execute function private.touch_updated_at();
drop trigger if exists shop_items_touch_updated_at on public.shop_items;
create trigger shop_items_touch_updated_at before update on public.shop_items
for each row execute function private.touch_updated_at();

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_username text := trim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  v_code text := coalesce(new.raw_user_meta_data ->> 'registration_code', '');
  v_is_admin boolean := lower(coalesce(new.email, '')) = 'tiamobew@gmail.com';
begin
  if v_is_admin then
    if v_username = '' then v_username := 'admin-' || left(new.id::text, 8); end if;
  else
    if length(v_username) < 2 or length(v_username) > 50 then
      raise exception 'ชื่อผู้ใช้ต้องยาว 2-50 ตัวอักษร';
    end if;
    if not exists (
      select 1 from private.app_settings
      where key = 'registration_code' and value = v_code
    ) then
      raise exception 'รหัสสมัครสมาชิกไม่ถูกต้อง';
    end if;
  end if;

  insert into public.profiles (
    id, username, full_name, class_name, student_no, role
  ) values (
    new.id,
    v_username,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'class_name', ''),
    coalesce(new.raw_user_meta_data ->> 'student_no', ''),
    case when v_is_admin then 'admin' else 'student' end
  );
  return new;
exception
  when unique_violation then
    raise exception 'ชื่อผู้ใช้นี้ถูกใช้แล้ว';
end;
$$;

drop trigger if exists on_auth_user_created_math_farm on auth.users;
create trigger on_auth_user_created_math_farm
after insert on auth.users
for each row execute function private.handle_new_auth_user();

insert into public.profiles(id, username, full_name, role, created_at)
select u.id,
       coalesce(nullif(trim(u.raw_user_meta_data ->> 'username'), ''), 'user-' || left(u.id::text, 8)),
       coalesce(u.raw_user_meta_data ->> 'full_name', ''),
       case when lower(coalesce(u.email, '')) = 'tiamobew@gmail.com' then 'admin' else 'student' end,
       u.created_at
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict do nothing;

alter table public.profiles enable row level security;
alter table public.missions enable row level security;
alter table public.questions enable row level security;
alter table public.shop_items enable row level security;
alter table public.mission_completions enable row level security;
alter table public.question_attempts enable row level security;

drop policy if exists profiles_select_own_or_admin on public.profiles;
create policy profiles_select_own_or_admin on public.profiles
for select to authenticated
using ((select auth.uid()) = id or (select private.is_admin()));
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles
for update to authenticated
using ((select private.is_admin())) with check ((select private.is_admin()));

drop policy if exists missions_read_authenticated on public.missions;
create policy missions_read_authenticated on public.missions
for select to authenticated using (active or (select private.is_admin()));
drop policy if exists missions_admin_all on public.missions;
drop policy if exists missions_admin_insert on public.missions;
create policy missions_admin_insert on public.missions for insert to authenticated
with check ((select private.is_admin()));
drop policy if exists missions_admin_update on public.missions;
create policy missions_admin_update on public.missions for update to authenticated
using ((select private.is_admin())) with check ((select private.is_admin()));
drop policy if exists missions_admin_delete on public.missions;
create policy missions_admin_delete on public.missions for delete to authenticated
using ((select private.is_admin()));

drop policy if exists questions_admin_all on public.questions;
create policy questions_admin_all on public.questions
for all to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

drop policy if exists shop_read_authenticated on public.shop_items;
create policy shop_read_authenticated on public.shop_items
for select to authenticated using (active or (select private.is_admin()));
drop policy if exists shop_admin_all on public.shop_items;
drop policy if exists shop_admin_insert on public.shop_items;
create policy shop_admin_insert on public.shop_items for insert to authenticated
with check ((select private.is_admin()));
drop policy if exists shop_admin_update on public.shop_items;
create policy shop_admin_update on public.shop_items for update to authenticated
using ((select private.is_admin())) with check ((select private.is_admin()));
drop policy if exists shop_admin_delete on public.shop_items;
create policy shop_admin_delete on public.shop_items for delete to authenticated
using ((select private.is_admin()));

drop policy if exists completions_select_own_or_admin on public.mission_completions;
create policy completions_select_own_or_admin on public.mission_completions
for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_admin()));
drop policy if exists attempts_select_own_or_admin on public.question_attempts;
create policy attempts_select_own_or_admin on public.question_attempts
for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_admin()));

revoke all on public.profiles, public.missions, public.questions, public.shop_items,
  public.mission_completions, public.question_attempts from anon;
revoke insert, delete on public.profiles from authenticated;
revoke insert, update, delete on public.mission_completions, public.question_attempts from authenticated;
grant select on public.profiles, public.missions, public.questions, public.shop_items, public.mission_completions, public.question_attempts to authenticated;
grant update on public.profiles to authenticated;
grant insert, update, delete on public.missions, public.questions, public.shop_items to authenticated;
grant usage on schema private to authenticated;
grant execute on function private.is_admin() to authenticated;

create or replace function public.get_my_profile()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'username', p.username, 'fullname', p.full_name, 'cls', p.class_name,
    'no', p.student_no, 'color', p.color, 'charName', p.character_name,
    'points', p.points, 'coins', p.coins, 'pets', p.pets, 'decor', p.decor,
    'role', p.role
  ) from public.profiles p where p.id = (select auth.uid());
$$;

create or replace function public.save_character(p_color text, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_color !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'สีไม่ถูกต้อง'; end if;
  update public.profiles set color = p_color, character_name = left(trim(p_name), 80)
  where id = auth.uid();
  return public.get_my_profile();
end;
$$;

create or replace function public.get_mission_dashboard()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'missions', coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'icon',m.icon,'title',m.title,'points',m.points) order by m.sort_order,m.created_at) from public.missions m where m.active), '[]'::jsonb),
    'doneToday', coalesce((select jsonb_agg(c.mission_id) from public.mission_completions c where c.user_id = auth.uid() and c.completed_on = (timezone('Asia/Bangkok', now()))::date), '[]'::jsonb),
    'totalDone', (select count(*) from public.mission_completions c where c.user_id = auth.uid()),
    'activeDays', (select count(distinct c.completed_on) from public.mission_completions c where c.user_id = auth.uid())
  );
$$;

create or replace function public.get_leaderboard()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'username', case when p.id = auth.uid() then p.username else '' end,
    'fullname', case when p.id = auth.uid() then p.full_name else '' end,
    'cls', p.class_name, 'color', p.color, 'charName', p.character_name, 'points', p.points
  ) order by p.points desc, p.created_at), '[]'::jsonb)
  from public.profiles p where p.role = 'student';
$$;

create or replace function public.get_farm()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'coins', p.coins, 'pets', p.pets, 'decor', p.decor, 'farmState', p.farm_state,
    'shop', coalesce((select jsonb_agg(jsonb_build_object('type',s.type,'id',s.id,'name',s.name,'emoji',s.emoji,'price',s.price) order by s.type,s.sort_order) from public.shop_items s where s.active), '[]'::jsonb)
  ) from public.profiles p where p.id = auth.uid();
$$;

create or replace function public.save_farm_state(p_state jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_state is null or jsonb_typeof(p_state) <> 'object' then raise exception 'ข้อมูลฟาร์มไม่ถูกต้อง'; end if;
  update public.profiles set farm_state = p_state where id = auth.uid();
  return p_state;
end;
$$;

create or replace function public.list_question_prompts()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'question',q.question,'coins',q.coins,'subject',q.subject) order by q.sort_order,q.created_at), '[]'::jsonb)
  from public.questions q where q.active;
$$;

create or replace function private.answers_equal(a text, b text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare x text := lower(regexp_replace(trim(coalesce(a,'')), '\\s+', '', 'g'));
declare y text := lower(regexp_replace(trim(coalesce(b,'')), '\\s+', '', 'g'));
begin
  return x = y;
end;
$$;

create or replace function public.submit_answer(p_question_id text, p_answer text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare q public.questions%rowtype;
declare v_correct boolean;
declare v_coins bigint;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into q from public.questions where id = p_question_id and active for share;
  if not found then raise exception 'ไม่พบคำถาม'; end if;
  v_correct := private.answers_equal(p_answer, q.answer);
  if v_correct then
    update public.profiles set coins = coins + q.coins where id = auth.uid() returning coins into v_coins;
  else
    select coins into v_coins from public.profiles where id = auth.uid();
  end if;
  insert into public.question_attempts(user_id, question_id, submitted_answer, correct, reward)
  values (auth.uid(), q.id, left(p_answer,500), v_correct, case when v_correct then q.coins else 0 end);
  return jsonb_build_object('correct',v_correct,'reward',case when v_correct then q.coins else 0 end,'coins',v_coins);
end;
$$;

create or replace function public.purchase_item(p_type text, p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare s public.shop_items%rowtype;
declare p public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into s from public.shop_items where type = p_type and id = p_item_id and active;
  if not found then raise exception 'ไม่พบสินค้า'; end if;
  update public.profiles
  set coins = coins - s.price,
      pets = case when p_type='pets' then jsonb_set(pets, array[p_item_id], to_jsonb(coalesce((pets->>p_item_id)::integer,0)+1), true) else pets end,
      decor = case when p_type='decor' then jsonb_set(decor, array[p_item_id], to_jsonb(coalesce((decor->>p_item_id)::integer,0)+1), true) else decor end
  where id = auth.uid() and coins >= s.price returning * into p;
  if not found then raise exception 'เหรียญไม่พอ'; end if;
  return jsonb_build_object('coins',p.coins,'pets',p.pets,'decor',p.decor);
end;
$$;

create or replace function public.complete_mission(p_mission_id text, p_photo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare m public.missions%rowtype;
declare v_points bigint;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_photo is not null and length(p_photo) > 1000000 then raise exception 'รูปมีขนาดใหญ่เกินไป'; end if;
  select * into m from public.missions where id = p_mission_id and active for share;
  if not found then raise exception 'ไม่พบภารกิจ'; end if;
  insert into public.mission_completions(user_id, mission_id, points_awarded, evidence_data_url)
  values (auth.uid(), m.id, m.points, nullif(p_photo,''));
  update public.profiles set points = points + m.points where id = auth.uid() returning points into v_points;
  return jsonb_build_object('points',v_points,'gained',m.points);
exception when unique_violation then
  raise exception 'ภารกิจนี้ทำวันนี้แล้ว พรุ่งนี้มาใหม่นะ';
end;
$$;

create or replace function public.admin_delete_user(p_username text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if not private.is_admin() then raise exception 'ไม่มีสิทธิ์ผู้ดูแล'; end if;
  select id into v_id from public.profiles where lower(username)=lower(p_username) and role <> 'admin';
  if v_id is null then raise exception 'ไม่พบผู้ใช้'; end if;
  delete from auth.users where id = v_id;
  return true;
end;
$$;

do $$
declare f regprocedure;
begin
  foreach f in array array[
    'public.get_my_profile()'::regprocedure,
    'public.save_character(text,text)'::regprocedure,
    'public.get_mission_dashboard()'::regprocedure,
    'public.get_leaderboard()'::regprocedure,
    'public.get_farm()'::regprocedure,
    'public.save_farm_state(jsonb)'::regprocedure,
    'public.list_question_prompts()'::regprocedure,
    'public.submit_answer(text,text)'::regprocedure,
    'public.purchase_item(text,text)'::regprocedure,
    'public.complete_mission(text,text)'::regprocedure,
    'public.admin_delete_user(text)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

insert into public.missions(id,icon,title,points,sort_order) values
('m1','📖','อ่านหนังสือ 20 นาที',10,1),
('m2','✏️','ทำแบบฝึกหัดคณิต 1 ชุด',15,2),
('m3','🔥','ท่องศัพท์อังกฤษ 10 คำ',10,3),
('m4','🔬','ทบทวนวิทยาศาสตร์ 1 บท',15,4),
('m5','✍️','เขียนบันทึกประจำวัน',5,5),
('m6','🧹','ช่วยงานบ้าน/รับผิดชอบหน้าที่',5,6)
on conflict (id) do nothing;

insert into public.questions(id,question,answer,coins,subject,sort_order) values
('q1','7 + 8 = ?','15',25,'คณิตศาสตร์',1),
('q2','12 × 3 = ?','36',25,'คณิตศาสตร์',2),
('q3','45 ÷ 9 = ?','5',25,'คณิตศาสตร์',3),
('q4','25 − 17 = ?','8',25,'คณิตศาสตร์',4),
('q5','6 × 7 = ?','42',25,'คณิตศาสตร์',5),
('q6','9 + 15 = ?','24',25,'คณิตศาสตร์',6),
('q7','100 − 64 = ?','36',25,'คณิตศาสตร์',7),
('q8','8 × 8 = ?','64',25,'คณิตศาสตร์',8)
on conflict (id) do nothing;

insert into public.shop_items(type,id,name,emoji,price,sort_order) values
('pets','chicken','ไก่','🐔',500,1),('pets','duck','เป็ด','🦆',800,2),
('pets','fish','ปลา','🐟',1000,3),('pets','pig','หมู','🐷',1500,4),
('decor','fence','รั้วไม้ (ต่อช่อง)','🪵',3000,1),('decor','flower','สวนดอกไม้','🌷',4000,2),
('decor','statue','รูปปั้น','🗿',6000,3),('decor','fountain','น้ำพุ','⛲',8000,4),
('decor','house','บ้าน','🏠',10000,5)
on conflict (type,id) do nothing;

do $$
declare t text;
begin
  foreach t in array array['profiles','missions','questions','shop_items'] loop
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
