-- ============================================================
-- BALUM ENTERTAINMENT
-- BANCO + AUTENTICAÇÃO + ÁLBUNS + STORAGE PRIVADO
-- ============================================================

create extension if not exists "pgcrypto";


-- ============================================================
-- 1. PERFIS DOS USUÁRIOS
-- ============================================================

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique,
  full_name text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);


-- ============================================================
-- 2. ÁLBUNS
-- ============================================================

create table if not exists public.albums (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  owner_id uuid not null
    references public.profiles(id)
    on delete cascade,
  created_at timestamptz not null default now()
);


-- ============================================================
-- 3. FOTOS E VÍDEOS
-- ============================================================

create table if not exists public.media (
  id uuid primary key default gen_random_uuid(),

  album_id uuid not null
    references public.albums(id)
    on delete cascade,

  storage_path text not null,
  file_name text not null,
  mime_type text,

  created_at timestamptz not null default now()
);


-- ============================================================
-- 4. ROW LEVEL SECURITY
-- ============================================================

alter table public.profiles enable row level security;
alter table public.albums enable row level security;
alter table public.media enable row level security;


-- ============================================================
-- 5. FUNÇÃO PARA VERIFICAR ADMIN
-- ============================================================

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select p.is_admin
      from public.profiles p
      where p.id = auth.uid()
    ),
    false
  );
$$;


-- ============================================================
-- 6. POLÍTICAS DOS PERFIS
-- ============================================================

drop policy if exists "profiles own or admin"
on public.profiles;

create policy "profiles own or admin"
on public.profiles
for select
using (
  id = auth.uid()
  or public.is_admin()
);


-- ============================================================
-- 7. POLÍTICAS DOS ÁLBUNS
-- ============================================================

drop policy if exists "albums owner or admin"
on public.albums;

create policy "albums owner or admin"
on public.albums
for select
using (
  owner_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "albums admin insert"
on public.albums;

create policy "albums admin insert"
on public.albums
for insert
with check (
  public.is_admin()
);


drop policy if exists "albums admin update"
on public.albums;

create policy "albums admin update"
on public.albums
for update
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


drop policy if exists "albums admin delete"
on public.albums;

create policy "albums admin delete"
on public.albums
for delete
using (
  public.is_admin()
);


-- ============================================================
-- 8. POLÍTICAS DOS ARQUIVOS
-- ============================================================

drop policy if exists "media owner or admin"
on public.media;

create policy "media owner or admin"
on public.media
for select
using (
  public.is_admin()

  or exists (
    select 1
    from public.albums a
    where a.id = media.album_id
      and a.owner_id = auth.uid()
  )
);


drop policy if exists "media admin insert"
on public.media;

create policy "media admin insert"
on public.media
for insert
with check (
  public.is_admin()
);


drop policy if exists "media admin update"
on public.media;

create policy "media admin update"
on public.media
for update
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


drop policy if exists "media admin delete"
on public.media;

create policy "media admin delete"
on public.media
for delete
using (
  public.is_admin()
);


-- ============================================================
-- 9. CRIAÇÃO AUTOMÁTICA DO PERFIL APÓS LOGIN GOOGLE
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

  insert into public.profiles (
    id,
    email,
    full_name
  )

  values (
    new.id,
    new.email,

    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      ''
    )
  )

  on conflict (id)
  do update
  set
    email = excluded.email,

    full_name =
      case
        when public.profiles.full_name is null
          or public.profiles.full_name = ''
        then excluded.full_name

        else public.profiles.full_name
      end;

  return new;

end;
$$;


-- ============================================================
-- 10. TRIGGER DO USUÁRIO
-- ============================================================

drop trigger if exists on_auth_user_created
on auth.users;

create trigger on_auth_user_created

after insert
on auth.users

for each row

execute procedure public.handle_new_user();


-- ============================================================
-- 11. CADASTRAR PERFIS DOS USUÁRIOS QUE JÁ EXISTIREM
-- ============================================================

insert into public.profiles (
  id,
  email,
  full_name
)

select
  id,
  email,

  coalesce(
    raw_user_meta_data ->> 'full_name',
    raw_user_meta_data ->> 'name',
    ''
  )

from auth.users

on conflict (id)
do update

set
  email = excluded.email;


-- ============================================================
-- 12. STORAGE PRIVADO DA BALUM
-- ============================================================

insert into storage.buckets (
  id,
  name,
  public
)

values (
  'event-media',
  'event-media',
  false
)

on conflict (id)
do update
set public = false;


-- ============================================================
-- 13. STORAGE:
--     CLIENTES PODEM VISUALIZAR SOMENTE
--     OS ARQUIVOS DOS SEUS ÁLBUNS
-- ============================================================

drop policy if exists "BALUM clientes podem visualizar seus arquivos"
on storage.objects;

create policy "BALUM clientes podem visualizar seus arquivos"

on storage.objects

for select

to authenticated

using (

  public.is_admin()

  or exists (

    select 1

    from public.albums a

    where a.id::text = split_part(storage.objects.name, '/', 1)

    and a.owner_id = auth.uid()

  )

);


-- ============================================================
-- 14. ADMIN PODE FAZER UPLOAD
-- ============================================================

drop policy if exists "BALUM admins podem enviar arquivos"
on storage.objects;

create policy "BALUM admins podem enviar arquivos"

on storage.objects

for insert

to authenticated

with check (
  public.is_admin()
);


-- ============================================================
-- 15. ADMIN PODE ATUALIZAR ARQUIVOS
-- ============================================================

drop policy if exists "BALUM admins podem atualizar arquivos"
on storage.objects;

create policy "BALUM admins podem atualizar arquivos"

on storage.objects

for update

to authenticated

using (
  public.is_admin()
)

with check (
  public.is_admin()
);


-- ============================================================
-- 16. ADMIN PODE EXCLUIR ARQUIVOS
-- ============================================================

drop policy if exists "BALUM admins podem excluir arquivos"
on storage.objects;

create policy "BALUM admins podem excluir arquivos"

on storage.objects

for delete

to authenticated

using (
  public.is_admin()
);


-- ============================================================
-- FIM
-- ============================================================
