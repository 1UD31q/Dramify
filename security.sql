-- =====================================================================
-- Dramify · защита базы (Row Level Security для таблицы kv_store)
-- Запускать в Supabase → SQL Editor целиком, один раз. Повторный запуск безопасен.
--
-- Что получится:
--   • не вошедшие — ничего не видят и не пишут;
--   • вошедшие через Google, но которых нет в списке сотрудников, — ничего не видят;
--   • сотрудники — читают данные, пишут только свои отметки, статусы заказов
--     и время продаж (attendance:log, app:ordersOverlay, saletime:*);
--   • тимлиды — плюс график выходных и список сотрудников;
--   • админы (app_metadata.role = 'admin') — всё.
-- =====================================================================

-- Список сотрудников из ключа app:employees (значение — JSON-строка).
-- security definer: функция читает таблицу в обход RLS, иначе правило
-- «сотрудник ли ты» не смогло бы само себя проверить.
create or replace function public.dramify_employees()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  raw text;
begin
  select value::text into raw from public.kv_store where key = 'app:employees';
  if raw is null then return '[]'::jsonb; end if;
  -- если колонка jsonb и в ней лежит строка — разворачиваем её
  if left(raw, 1) = '"' then raw := raw::jsonb #>> '{}'; end if;
  return coalesce(raw::jsonb, '[]'::jsonb);
exception when others then
  return '[]'::jsonb;
end;
$$;

create or replace function public.dramify_is_admin()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin';
$$;

-- Сотрудник = его почта есть в списке сотрудников
create or replace function public.dramify_is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.dramify_is_admin() or exists (
    select 1 from jsonb_array_elements(public.dramify_employees()) e
    where lower(coalesce(e ->> 'email', '')) <> ''
      and lower(e ->> 'email') = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

create or replace function public.dramify_is_teamlead()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from jsonb_array_elements(public.dramify_employees()) e
    where lower(coalesce(e ->> 'email', '')) <> ''
      and lower(e ->> 'email') = lower(coalesce(auth.jwt() ->> 'email', ''))
      and e ->> 'role' = 'teamlead'
  );
$$;

-- Может ли текущий пользователь записывать этот ключ
create or replace function public.dramify_can_write(k text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.dramify_is_admin()
    or (public.dramify_is_staff() and (
          k in ('attendance:log', 'app:ordersOverlay')
          or k like 'saletime:%'))
    or (public.dramify_is_teamlead() and k in ('app:schedules', 'app:employees'));
$$;

-- Включаем RLS и убираем все старые правила (часто там «разрешено всем»)
alter table public.kv_store enable row level security;

do $$
declare p record;
begin
  for p in select policyname from pg_policies
           where schemaname = 'public' and tablename = 'kv_store'
  loop
    execute format('drop policy %I on public.kv_store', p.policyname);
  end loop;
end $$;

create policy dramify_read on public.kv_store
  for select to authenticated
  using (public.dramify_is_staff());

create policy dramify_insert on public.kv_store
  for insert to authenticated
  with check (public.dramify_can_write(key));

create policy dramify_update on public.kv_store
  for update to authenticated
  using (public.dramify_can_write(key))
  with check (public.dramify_can_write(key));

create policy dramify_delete on public.kv_store
  for delete to authenticated
  using (public.dramify_is_admin());

-- Не вошедшим (роль anon) — никакого доступа к таблице вообще
revoke all on public.kv_store from anon;

-- Проверка: должно показать 4 правила dramify_*
select policyname, cmd from pg_policies
where schemaname = 'public' and tablename = 'kv_store'
order by policyname;
