alter table public.profiles
  add column if not exists pet_food integer not null default 0;

alter table public.profiles
  drop constraint if exists profiles_pet_food_check;
alter table public.profiles
  add constraint profiles_pet_food_check check (pet_food between 0 and 100000);

alter table public.profiles
  add column if not exists pet_styles jsonb not null default '{}'::jsonb;

alter table public.profiles
  drop constraint if exists profiles_pet_styles_check;
alter table public.profiles
  add constraint profiles_pet_styles_check check (jsonb_typeof(pet_styles) = 'object');

alter table public.shop_items
  drop constraint if exists shop_items_type_check;
alter table public.shop_items
  add constraint shop_items_type_check check (type in ('pets', 'decor', 'food'));

insert into public.shop_items(type, id, name, emoji, price, active, sort_order)
values ('food', 'pet_treat', 'อาหารสัตว์แสนอร่อย', '🥕', 150, true, 1)
on conflict (type, id) do update
set name = excluded.name,
    emoji = excluded.emoji,
    active = true;

create or replace function public.get_farm()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'coins', p.coins,
    'pets', p.pets,
    'decor', p.decor,
    'petFood', p.pet_food,
    'petStyles', p.pet_styles,
    'farmState', p.farm_state,
    'shop', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'type', s.type,
          'id', s.id,
          'name', s.name,
          'emoji', s.emoji,
          'price', s.price
        ) order by s.type, s.sort_order
      )
      from public.shop_items s
      where s.active
    ), '[]'::jsonb)
  )
  from public.profiles p
  where p.id = auth.uid();
$$;

create or replace function public.purchase_item(p_type text, p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.shop_items%rowtype;
  p public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_type not in ('pets', 'decor', 'food') then raise exception 'ประเภทสินค้าไม่ถูกต้อง'; end if;

  select * into s
  from public.shop_items
  where type = p_type and id = p_item_id and active;
  if not found then raise exception 'ไม่พบสินค้า'; end if;

  update public.profiles
  set coins = coins - s.price,
      pets = case
        when p_type = 'pets' then jsonb_set(
          pets, array[p_item_id], to_jsonb(coalesce((pets ->> p_item_id)::integer, 0) + 1), true
        ) else pets end,
      decor = case
        when p_type = 'decor' then jsonb_set(
          decor, array[p_item_id], to_jsonb(coalesce((decor ->> p_item_id)::integer, 0) + 1), true
        ) else decor end,
      pet_food = case when p_type = 'food' then pet_food + 1 else pet_food end
  where id = auth.uid() and coins >= s.price
  returning * into p;

  if not found then raise exception 'เหรียญไม่พอ'; end if;

  return jsonb_build_object(
    'coins', p.coins,
    'pets', p.pets,
    'decor', p.decor,
    'petFood', p.pet_food,
    'petStyles', p.pet_styles
  );
end;
$$;

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
  if p_pet_key !~ '^(chicken|duck|fish|pig):[0-9]+$' then
    raise exception 'รหัสสัตว์ไม่ถูกต้อง';
  end if;
  if p_accessory not in ('hat', 'bow', 'bag', 'color_pink', 'color_blue', 'color_gold') then
    raise exception 'ของตกแต่งไม่ถูกต้อง';
  end if;

  v_type := split_part(p_pet_key, ':', 1);
  v_index := split_part(p_pet_key, ':', 2)::integer;

  select * into p
  from public.profiles
  where id = auth.uid()
  for update;
  if not found then raise exception 'ไม่พบผู้เล่น'; end if;

  v_owned := coalesce((p.pets ->> v_type)::integer, 0);
  if v_index < 0 or v_index >= v_owned then raise exception 'ไม่พบสัตว์ตัวนี้'; end if;
  if p.pet_food < 1 then raise exception 'อาหารสัตว์หมดแล้ว'; end if;

  update public.profiles
  set pet_food = pet_food - 1,
      pet_styles = jsonb_set(pet_styles, array[p_pet_key], to_jsonb(p_accessory), true)
  where id = auth.uid()
  returning * into p;

  return jsonb_build_object(
    'petFood', p.pet_food,
    'petStyles', p.pet_styles,
    'petKey', p_pet_key,
    'accessory', p_accessory
  );
end;
$$;

revoke all on function public.purchase_item(text, text) from public, anon;
grant execute on function public.purchase_item(text, text) to authenticated;
revoke all on function public.feed_pet(text, text) from public, anon;
grant execute on function public.feed_pet(text, text) to authenticated;
