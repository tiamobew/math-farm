create or replace function public.internal_registration_code_for_service_role()
returns text
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_code text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'permission denied';
  end if;

  select value into v_code
  from private.app_settings
  where key = 'registration_code';

  if v_code is null or v_code = '' then
    raise exception 'registration code is not configured';
  end if;

  return v_code;
end;
$$;

revoke all on function public.internal_registration_code_for_service_role() from public, anon, authenticated;
grant execute on function public.internal_registration_code_for_service_role() to service_role;

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
