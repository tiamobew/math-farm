insert into public.shop_items(type, id, name, emoji, price, active, sort_order)
values
  ('pets', 'cow', 'วัว', '🐄', 2000, true, 5),
  ('pets', 'pug', 'สุนัขปั๊ก', '🐶', 2500, true, 6)
on conflict (type, id) do update
set name = excluded.name,
    emoji = excluded.emoji,
    active = true,
    sort_order = excluded.sort_order;

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
  if p_pet_key !~ '^(chicken|duck|fish|pig|cow|pug):[0-9]+$' then
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

revoke all on function public.feed_pet(text, text) from public, anon;
grant execute on function public.feed_pet(text, text) to authenticated;
