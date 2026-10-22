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
