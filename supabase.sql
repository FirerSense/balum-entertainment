-- BALUM / SUPABASE
-- Execute este SQL no SQL Editor do Supabase.

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique,
  full_name text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.albums (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.media (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.albums(id) on delete cascade,
  storage_path text not null,
  file_name text not null,
  mime_type text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.albums enable row level security;
alter table public.media enable row level security;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

drop policy if exists "profiles own or admin" on public.profiles;
create policy "profiles own or admin" on public.profiles
for select using (id = auth.uid() or public.is_admin());

drop policy if exists "albums owner or admin" on public.albums;
create policy "albums owner or admin" on public.albums
for select using (owner_id = auth.uid() or public.is_admin());

drop policy if exists "albums admin insert" on public.albums;
create policy "albums admin insert" on public.albums
for insert with check (public.is_admin());

drop policy if exists "albums admin update" on public.albums;
create policy "albums admin update" on public.albums
for update using (public.is_admin()) with check (public.is_admin());

drop policy if exists "albums admin delete" on public.albums;
create policy "albums admin delete" on public.albums
for delete using (public.is_admin());

drop policy if exists "media album owner or admin" on public.media;
create policy "media album owner or admin" on public.media
for select using (
  public.is_admin() or exists (
    select 1 from public.albums a where a.id = album_id and a.owner_id = auth.uid()
  )
);

drop policy if exists "media admin insert" on public.media;
create policy "media admin insert" on public.media
for insert with check (public.is_admin());

drop policy if exists "media admin delete" on public.media;
create policy "media admin delete" on public.media
for delete using (public.is_admin());

-- Cria o perfil automaticamente quando alguém entra com Google.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(id,email,full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', '')
  )
  on conflict (id) do update
    set email = excluded.email,
        full_name = case when public.profiles.full_name = '' then excluded.full_name else public.profiles.full_name end;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Storage:
-- Crie manualmente no painel do Supabase um bucket chamado:
-- event-media
-- Deixe o bucket PRIVADO.
--
-- Depois crie políticas de Storage permitindo somente admin fazer upload/delete
-- e usuários autenticados acessarem objetos que correspondam aos álbuns aos
-- quais eles têm acesso. Para máxima segurança em produção, use uma Edge
-- Function para emitir URLs assinadas após validar album_id/owner_id.
