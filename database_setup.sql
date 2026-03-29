-- Supabase Schema for Music Creator Platform

-- 1. Profiles Table
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID references auth.users not null primary key,
  username text,
  avatar_url text
);

-- Row Level Security for profiles
alter table public.profiles enable row level security;

-- Safely create policies (Postgres doesn't have CREATE POLICY IF NOT EXISTS, so we drop them first if needed, 
-- or you can just ignore errors if they say "policy already exists")
-- (To keep things simple, we wrap policy creation in a try/catch equivalent or just assume they might fail if running twice)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Public profiles are viewable by everyone.'
    ) THEN
        create policy "Public profiles are viewable by everyone." on profiles for select using (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can insert their own profile.'
    ) THEN
        create policy "Users can insert their own profile." on profiles for insert with check (auth.uid() = id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can update own profile.'
    ) THEN
        create policy "Users can update own profile." on profiles for update using (auth.uid() = id);
    END IF;
END $$;


-- 2. Projects Table
CREATE TABLE IF NOT EXISTS public.projects (
  id UUID default gen_random_uuid() primary key,
  user_id UUID references public.profiles(id) not null,
  title text not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- RLS for projects
alter table public.projects enable row level security;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'projects' AND policyname = 'Users can view their own projects.'
    ) THEN
        create policy "Users can view their own projects." on projects for select using (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'projects' AND policyname = 'Users can insert their own projects.'
    ) THEN
        create policy "Users can insert their own projects." on projects for insert with check (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'projects' AND policyname = 'Users can update own projects.'
    ) THEN
        create policy "Users can update own projects." on projects for update using (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'projects' AND policyname = 'Users can delete own projects.'
    ) THEN
        create policy "Users can delete own projects." on projects for delete using (auth.uid() = user_id);
    END IF;
END $$;


-- 3. Tracks Table
CREATE TABLE IF NOT EXISTS public.tracks (
  id UUID default gen_random_uuid() primary key,
  project_id UUID references public.projects(id) on delete cascade not null,
  name text not null,
  audio_url text not null,
  volume float default 1.0,
  is_muted boolean default false,
  color text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- RLS for tracks
alter table public.tracks enable row level security;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'tracks' AND policyname = 'Users can view tracks of their projects.'
    ) THEN
        create policy "Users can view tracks of their projects." on tracks for select using (
          exists (select 1 from public.projects where projects.id = tracks.project_id and projects.user_id = auth.uid())
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'tracks' AND policyname = 'Users can insert tracks to their projects.'
    ) THEN
        create policy "Users can insert tracks to their projects." on tracks for insert with check (
          exists (select 1 from public.projects where projects.id = tracks.project_id and projects.user_id = auth.uid())
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'tracks' AND policyname = 'Users can update tracks of their projects.'
    ) THEN
        create policy "Users can update tracks of their projects." on tracks for update using (
          exists (select 1 from public.projects where projects.id = tracks.project_id and projects.user_id = auth.uid())
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'tracks' AND policyname = 'Users can delete tracks of their projects.'
    ) THEN
        create policy "Users can delete tracks of their projects." on tracks for delete using (
          exists (select 1 from public.projects where projects.id = tracks.project_id and projects.user_id = auth.uid())
        );
    END IF;
END $$;


-- 4. Storage Buckets
-- Insert bucket only if it doesn't already exist
insert into storage.buckets (id, name, public) 
select 'audio_tracks', 'audio_tracks', true
where not exists (
    select 1 from storage.buckets where id = 'audio_tracks'
);

-- Storage bucket access policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname = 'Audio tracks are publicly accessible.'
    ) THEN
        create policy "Audio tracks are publicly accessible." 
        on storage.objects for select 
        using (bucket_id = 'audio_tracks');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname = 'Authenticated users can upload audio tracks.'
    ) THEN
        create policy "Authenticated users can upload audio tracks." 
        on storage.objects for insert 
        with check (bucket_id = 'audio_tracks' and auth.role() = 'authenticated');
    END IF;
END $$;
