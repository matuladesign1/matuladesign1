-- Sermons de Branham Matomate — schéma serveur (Supabase / PostgreSQL)
-- Recherche plein texte + recherche vectorielle (pgvector), rôles et sécurité (RLS).

create extension if not exists vector;
create extension if not exists unaccent;

-- ---------------------------------------------------------------- rôles
create type app_role as enum ('super_admin', 'admin', 'traducteur', 'editeur', 'utilisateur');

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text,
  role app_role not null default 'utilisateur',
  created_at timestamptz not null default now()
);

create or replace function has_role(roles app_role[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = any(roles));
$$;

-- ---------------------------------------------------------------- contenu
create table sermons (
  id bigserial primary key,
  code text not null,
  language text not null,
  title text not null,
  date date,
  year int,
  location text,
  duration_sec int,
  series text,
  audio_url text,
  source text not null,              -- provenance + autorisation
  sha1 text,
  translation_status text not null default 'original'
    check (translation_status in ('original', 'officielle', 'ia_non_validee', 'validee')),
  validated_by uuid references profiles(id),
  validated_at timestamptz,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  unique (code, language)
);

-- unaccent n'est pas IMMUTABLE : enveloppe pour la colonne générée
create or replace function unaccent_immutable(t text) returns text
language sql immutable parallel safe as $$ select public.unaccent('public.unaccent', t) $$;

create table paragraphs (
  id bigserial primary key,
  sermon_id bigint not null references sermons on delete cascade,
  number int not null,
  text text not null,
  start_ms int,
  tsv tsvector generated always as (to_tsvector('french', unaccent_immutable(text))) stored,
  embedding vector(1536),
  unique (sermon_id, number)
);

create index paragraphs_tsv on paragraphs using gin (tsv);
create index paragraphs_embedding on paragraphs using hnsw (embedding vector_cosine_ops);

-- Recherche par le sens (appelée par la fonction « assistant »)
create or replace function match_paragraphs(query_embedding vector(1536), match_count int default 20)
returns table (code text, language text, number int, score float)
language sql stable as $$
  select s.code, s.language, p.number, 1 - (p.embedding <=> query_embedding) as score
  from paragraphs p join sermons s on s.id = p.sermon_id
  where s.published and p.embedding is not null
  order by p.embedding <=> query_embedding
  limit match_count;
$$;

-- ---------------------------------------------------------------- données utilisateur (synchronisation)
create table user_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  title text not null default '',
  body text not null default '',
  ref_type text, ref_key text, ref_label text, collection text,
  updated_at timestamptz not null default now()
);
create table user_favorites (
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  ref_type text not null, ref_key text not null, label text not null, excerpt text,
  created_at timestamptz not null default now(),
  primary key (user_id, ref_type, ref_key)
);

-- ---------------------------------------------------------------- sécurité
alter table profiles enable row level security;
alter table sermons enable row level security;
alter table paragraphs enable row level security;
alter table user_notes enable row level security;
alter table user_favorites enable row level security;

create policy "profil personnel" on profiles for select using (id = auth.uid() or has_role(array['super_admin','admin']::app_role[]));
create policy "gestion des rôles" on profiles for update using (has_role(array['super_admin']::app_role[]));

create policy "lecture publiée" on sermons for select using (published or has_role(array['super_admin','admin','traducteur','editeur']::app_role[]));
create policy "édition" on sermons for all using (has_role(array['super_admin','admin','editeur']::app_role[]));
create policy "validation traduction" on sermons for update using (has_role(array['traducteur']::app_role[]) and language = 'ln');

create policy "lecture paragraphes" on paragraphs for select using (
  exists (select 1 from sermons s where s.id = sermon_id and (s.published or has_role(array['super_admin','admin','traducteur','editeur']::app_role[]))));
create policy "édition paragraphes" on paragraphs for all using (has_role(array['super_admin','admin','editeur','traducteur']::app_role[]));

create policy "mes notes" on user_notes for all using (user_id = auth.uid());
create policy "mes favoris" on user_favorites for all using (user_id = auth.uid());
