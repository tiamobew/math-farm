alter table public.profiles
  add column if not exists character_type text not null default 'cloud';

alter table public.profiles
  drop constraint if exists profiles_character_type_check;

alter table public.profiles
  add constraint profiles_character_type_check
  check (character_type in ('cloud', 'nature', 'builder'));

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
    'charType', p.character_type,
    'points', p.points, 'coins', p.coins, 'pets', p.pets, 'decor', p.decor,
    'role', p.role
  ) from public.profiles p where p.id = (select auth.uid());
$$;

create or replace function public.save_character(p_color text, p_name text, p_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_color !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'สีไม่ถูกต้อง'; end if;
  if p_type not in ('cloud', 'nature', 'builder') then raise exception 'รูปแบบตัวละครไม่ถูกต้อง'; end if;
  update public.profiles
  set color = p_color,
      character_name = left(trim(p_name), 80),
      character_type = p_type
  where id = auth.uid();
  return public.get_my_profile();
end;
$$;

grant execute on function public.save_character(text, text, text) to authenticated;
