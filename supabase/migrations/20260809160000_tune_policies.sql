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

grant update on public.profiles to authenticated;
alter function public.get_my_profile() security invoker;
alter function public.get_mission_dashboard() security invoker;
alter function public.get_farm() security invoker;
