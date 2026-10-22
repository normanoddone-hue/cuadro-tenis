-- Cuadro de Tenis · estructura en Supabase
-- Ejecutar una sola vez en: Supabase → SQL Editor → New query → pegar todo → Run

-- 1) Estado de la app. Dos filas:
--    'principal' = todo lo público (torneos, cuadros, resultados, ranking, noticias, galería)
--    'privado'   = cédula, teléfono y fecha de nacimiento de los jugadores (solo administrador)
create table if not exists public.club_estado (
  id         text primary key check (id in ('principal','privado')),
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.club_estado enable row level security;

drop policy if exists "publico lee principal"   on public.club_estado;
drop policy if exists "admin lee todo"          on public.club_estado;
drop policy if exists "admin inserta"           on public.club_estado;
drop policy if exists "admin actualiza"         on public.club_estado;

-- Cualquiera (sin cuenta) puede leer la parte pública
create policy "publico lee principal" on public.club_estado
  for select to anon, authenticated using (id = 'principal');

-- Solo usuarios con sesión (los administradores que vos creás) leen lo privado y escriben
create policy "admin lee todo" on public.club_estado
  for select to authenticated using (true);
create policy "admin inserta" on public.club_estado
  for insert to authenticated with check (true);
create policy "admin actualiza" on public.club_estado
  for update to authenticated using (true) with check (true);

-- Actualización en vivo para el público cuando el administrador carga un resultado
do $$ begin
  alter publication supabase_realtime add table public.club_estado;
exception when duplicate_object then null; end $$;

-- 2) Fotos (galería y fotos de perfil): bucket público de solo lectura
insert into storage.buckets (id, name, public)
values ('fotos', 'fotos', true)
on conflict (id) do update set public = true;

drop policy if exists "fotos lectura publica" on storage.objects;
drop policy if exists "fotos admin sube"      on storage.objects;
drop policy if exists "fotos admin borra"     on storage.objects;

create policy "fotos lectura publica" on storage.objects
  for select to anon, authenticated using (bucket_id = 'fotos');
create policy "fotos admin sube" on storage.objects
  for insert to authenticated with check (bucket_id = 'fotos');
create policy "fotos admin borra" on storage.objects
  for delete to authenticated using (bucket_id = 'fotos');

-- 5) INSCRIPCIÓN ONLINE (agregado en la versión con 12 mejoras)
--    El público puede enviar pedidos de inscripción; solo los administradores los leen, aprueban o borran.
--    Si ya ejecutaste este archivo antes, podés ejecutar solo este bloque.
create table if not exists public.tenis_solicitudes (
  id      uuid primary key default gen_random_uuid(),
  torneo  text not null check (char_length(torneo) between 1 and 40),
  data    jsonb not null check (pg_column_size(data) < 4000),
  creado  timestamptz not null default now()
);
alter table public.tenis_solicitudes enable row level security;
drop policy if exists "tenis publico pide inscripcion" on public.tenis_solicitudes;
drop policy if exists "tenis admin lee solicitudes"    on public.tenis_solicitudes;
drop policy if exists "tenis admin borra solicitudes"  on public.tenis_solicitudes;
create policy "tenis publico pide inscripcion" on public.tenis_solicitudes
  for insert to anon, authenticated with check (true);
create policy "tenis admin lee solicitudes" on public.tenis_solicitudes
  for select to authenticated using (public.tenis_es_admin());
create policy "tenis admin borra solicitudes" on public.tenis_solicitudes
  for delete to authenticated using (public.tenis_es_admin());

-- 6) BUSCAR JUGADOR POR CÉDULA AL INSCRIBIRSE
--    Responde solo si la cédula está registrada (y el nombre, categoría y rama), sin mostrar cédulas al público.
create or replace function public.tenis_buscar_cedula(ci text, torneo_id text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare priv jsonb; pub jsonb; pid text; j jsonb; cat jsonb; ins boolean := false;
begin
  ci := regexp_replace(coalesce(ci,''), '\D', '', 'g');
  if length(ci) < 5 then return jsonb_build_object('existe', false); end if;
  select data into priv from tenis_estado where id = 'privado';
  select key into pid from jsonb_each(coalesce(priv,'{}'::jsonb)) where value->>'cedula' = ci limit 1;
  if pid is null then return jsonb_build_object('existe', false); end if;
  select data into pub from tenis_estado where id = 'principal';
  select x into j from jsonb_array_elements(coalesce(pub->'jugadores','[]'::jsonb)) x where x->>'id' = pid limit 1;
  select c into cat from jsonb_array_elements(coalesce(pub->'torneos','[]'::jsonb)) t, jsonb_array_elements(coalesce(t->'categorias','[]'::jsonb)) c where c->>'id' = torneo_id limit 1;
  if cat is not null then
    ins := exists(select 1 from jsonb_array_elements(coalesce(cat->'inscriptos','[]'::jsonb)) e, jsonb_array_elements_text(coalesce(e->'j','[]'::jsonb)) k where k = pid);
  end if;
  return jsonb_build_object('existe', true, 'nombre', j->>'nombre', 'categoria', coalesce(j->>'categoria',''), 'sexo', j->>'sexo', 'inscripto', ins);
end $$;
grant execute on function public.tenis_buscar_cedula(text, text) to anon, authenticated;

-- 7) VARIOS CLUBES EN UNA SOLA INSTALACIÓN
--    Cada club tiene un código y su dirección es  https://tu-app/?club=codigo
--    El club que ya tenés pasa a ser el club "principal" (su dirección no cambia y sus datos no se tocan).
--    Los administradores actuales (tabla tenis_admins) quedan como SUPERADMINISTRADORES: ven todos los clubes y dan de alta clubes nuevos.
--    Ejecutar este bloque una sola vez (se puede volver a ejecutar sin problema).

create table if not exists public.tenis_clubes (
  slug   text primary key check (slug ~ '^[a-z0-9-]{2,30}$' and slug <> 'privado'),
  nombre text not null check (char_length(nombre) between 1 and 80),
  creado timestamptz not null default now()
);
alter table public.tenis_clubes enable row level security;
drop policy if exists "tenis clubes lectura" on public.tenis_clubes;
create policy "tenis clubes lectura" on public.tenis_clubes for select to anon, authenticated using (true);
insert into public.tenis_clubes(slug, nombre)
  select 'principal', coalesce(nullif((select data->>'club' from public.tenis_estado where id = 'principal'), ''), 'Club principal')
  on conflict do nothing;

create table if not exists public.tenis_superadmins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.tenis_superadmins enable row level security;   -- sin políticas: solo se usa desde las funciones
insert into public.tenis_superadmins(user_id)
  select a.user_id::uuid from public.tenis_admins a where exists(select 1 from auth.users u where u.id = a.user_id::uuid)
  on conflict do nothing;

create table if not exists public.tenis_club_admins (
  user_id uuid not null references auth.users(id) on delete cascade,
  club    text not null references public.tenis_clubes(slug) on delete cascade,
  primary key (user_id, club)
);
alter table public.tenis_club_admins enable row level security;   -- sin políticas: solo se usa desde las funciones
insert into public.tenis_club_admins(user_id, club)
  select a.user_id::uuid, 'principal' from public.tenis_admins a where exists(select 1 from auth.users u where u.id = a.user_id::uuid)
  on conflict do nothing;

create or replace function public.tenis_es_super() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from tenis_superadmins where user_id = auth.uid())
$$;
create or replace function public.tenis_admin_de(p_club text) returns boolean
language sql stable security definer set search_path = public as $$
  select tenis_es_super() or exists(select 1 from tenis_club_admins where user_id = auth.uid() and club = p_club)
$$;
-- 'principal' y 'privado' son del club principal; los demás clubes usan 'codigo' y 'codigo:privado'
create or replace function public.tenis_club_de(p_id text) returns text
language sql immutable as $$
  select case when p_id in ('principal','privado') then 'principal' else split_part(p_id, ':', 1) end
$$;
-- "Es administrador de algún club" (lo usan las fotos)
create or replace function public.tenis_es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from tenis_admins where user_id::text = auth.uid()::text)
      or exists(select 1 from tenis_club_admins where user_id = auth.uid())
      or exists(select 1 from tenis_superadmins where user_id = auth.uid())
$$;
grant execute on function public.tenis_es_super(), public.tenis_admin_de(text), public.tenis_club_de(text), public.tenis_es_admin() to anon, authenticated;

-- Datos de cada club: el público lee lo público; cada administrador lee y escribe solo su club
do $$ declare r record; begin
  for r in select policyname from pg_policies where schemaname = 'public' and tablename = 'tenis_estado' loop
    execute format('drop policy %I on public.tenis_estado', r.policyname);
  end loop;
  for r in select conname from pg_constraint where conrelid = 'public.tenis_estado'::regclass and contype = 'c' loop
    execute format('alter table public.tenis_estado drop constraint %I', r.conname);
  end loop;
end $$;
alter table public.tenis_estado add constraint tenis_estado_id_ok check (id ~ '^[a-z0-9-]{2,30}(:privado)?$');
alter table public.tenis_estado enable row level security;
create policy "tenis estado publico" on public.tenis_estado
  for select to anon, authenticated using (id <> 'privado' and id !~ ':privado$');
create policy "tenis estado admin lee" on public.tenis_estado
  for select to authenticated using (public.tenis_admin_de(public.tenis_club_de(id)));
create policy "tenis estado admin inserta" on public.tenis_estado
  for insert to authenticated with check (public.tenis_admin_de(public.tenis_club_de(id))
    and exists(select 1 from public.tenis_clubes c where c.slug = public.tenis_club_de(id)));
create policy "tenis estado admin actualiza" on public.tenis_estado
  for update to authenticated using (public.tenis_admin_de(public.tenis_club_de(id)))
  with check (public.tenis_admin_de(public.tenis_club_de(id)));

-- Pedidos de inscripción online, separados por club
alter table public.tenis_solicitudes add column if not exists club text not null default 'principal';
drop policy if exists "tenis publico pide inscripcion" on public.tenis_solicitudes;
drop policy if exists "tenis admin lee solicitudes"    on public.tenis_solicitudes;
drop policy if exists "tenis admin borra solicitudes"  on public.tenis_solicitudes;
create policy "tenis publico pide inscripcion" on public.tenis_solicitudes
  for insert to anon, authenticated with check (exists(select 1 from public.tenis_clubes c where c.slug = club));
create policy "tenis admin lee solicitudes" on public.tenis_solicitudes
  for select to authenticated using (public.tenis_admin_de(club));
create policy "tenis admin borra solicitudes" on public.tenis_solicitudes
  for delete to authenticated using (public.tenis_admin_de(club));

-- Buscar por cédula dentro de un club
create or replace function public.tenis_buscar_cedula_club(ci text, torneo_id text, p_club text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare priv jsonb; pub jsonb; pid text; j jsonb; cat jsonb; ins boolean := false; idpub text; idpriv text;
begin
  idpub  := case when p_club = 'principal' then 'principal' else p_club end;
  idpriv := case when p_club = 'principal' then 'privado' else p_club || ':privado' end;
  ci := regexp_replace(coalesce(ci,''), '\D', '', 'g');
  if length(ci) < 5 then return jsonb_build_object('existe', false); end if;
  select data into priv from tenis_estado where id = idpriv;
  select key into pid from jsonb_each(coalesce(priv,'{}'::jsonb)) where key <> '_pagos' and value->>'cedula' = ci limit 1;
  if pid is null then return jsonb_build_object('existe', false); end if;
  select data into pub from tenis_estado where id = idpub;
  select x into j from jsonb_array_elements(coalesce(pub->'jugadores','[]'::jsonb)) x where x->>'id' = pid limit 1;
  select c into cat from jsonb_array_elements(coalesce(pub->'torneos','[]'::jsonb)) t, jsonb_array_elements(coalesce(t->'categorias','[]'::jsonb)) c where c->>'id' = torneo_id limit 1;
  if cat is not null then
    ins := exists(select 1 from jsonb_array_elements(coalesce(cat->'inscriptos','[]'::jsonb)) e, jsonb_array_elements_text(coalesce(e->'j','[]'::jsonb)) k where k = pid);
  end if;
  return jsonb_build_object('existe', true, 'nombre', j->>'nombre', 'categoria', coalesce(j->>'categoria',''), 'sexo', j->>'sexo', 'inscripto', ins);
end $$;
grant execute on function public.tenis_buscar_cedula_club(text, text, text) to anon, authenticated;

-- Alta de clubes y administradores (solo superadministrador)
create or replace function public.tenis_alta_club(p_slug text, p_nombre text, p_email text)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare uid uuid; nuevo boolean;
begin
  if not tenis_es_super() then raise exception 'Solo el superadministrador puede dar de alta clubes'; end if;
  p_slug := lower(trim(coalesce(p_slug,'')));
  if p_slug !~ '^[a-z0-9-]{2,30}$' or p_slug = 'privado' then raise exception 'Código de club inválido'; end if;
  nuevo := not exists(select 1 from tenis_clubes where slug = p_slug);
  insert into tenis_clubes(slug, nombre) values (p_slug, coalesce(nullif(trim(p_nombre),''), p_slug)) on conflict (slug) do nothing;
  select id into uid from auth.users where lower(email) = lower(trim(coalesce(p_email,''))) limit 1;
  if uid is not null then
    begin update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()) where id = uid; exception when others then null; end;
    insert into tenis_club_admins(user_id, club) values (uid, p_slug) on conflict do nothing;
  end if;
  return jsonb_build_object('ok', true, 'nuevo', nuevo, 'admin', uid is not null);
end $$;
revoke all on function public.tenis_alta_club(text, text, text) from public, anon;
grant execute on function public.tenis_alta_club(text, text, text) to authenticated;

create or replace function public.tenis_listar_clubes() returns jsonb
language sql stable security definer set search_path = public, auth as $$
  select case when tenis_es_super() then coalesce((
    select jsonb_agg(jsonb_build_object('slug', c.slug, 'nombre', c.nombre, 'creado', c.creado,
      'admins', (select coalesce(jsonb_agg(u.email order by u.email), '[]'::jsonb)
                 from tenis_club_admins a join auth.users u on u.id = a.user_id where a.club = c.slug)) order by c.creado)
    from tenis_clubes c), '[]'::jsonb) else '[]'::jsonb end
$$;
grant execute on function public.tenis_listar_clubes() to authenticated;
