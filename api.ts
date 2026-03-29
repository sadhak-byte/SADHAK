import { supabase } from './supabase';
import { AudioTrack } from '@/types/studio';

// For simplicity in a prototype without full Auth UI, we will just simulate a user
// Next.js with Supabase usually uses an Auth flow to get the user ID, but we will mock one
// if it doesn't exist to satisfy the foreign keys.

async function getOrCreateMockUser() {
  const { data: { user } } = await supabase.auth.getUser();
  if (user) return user;

  // We are using anonymous login to bypass email/password for the prototype
  const { data: authData, error: authError } = await supabase.auth.signInAnonymously();
  if (authError || !authData.user) {
    console.error('Anonymous auth failed:', authError);
    throw new Error('Could not authenticate user anonymously');
  }

  // Ensure a profile exists for this new user
  const { error: profileError } = await supabase
    .from('profiles')
    .upsert({ id: authData.user.id, username: 'Guest Producer', avatar_url: '' }, { onConflict: 'id' });
    
  if (profileError) {
    console.warn('Profile creation issue:', profileError.message);
  }

  return authData.user;
}

export async function saveProject(title: string, tracks: AudioTrack[]) {
  try {
    const user = await getOrCreateMockUser();
    
    // 1. Create the project
    const { data: project, error: projectError } = await supabase
      .from('projects')
      .insert({
        user_id: user.id,
        title: title || 'Untitled Project',
      })
      .select('id')
      .single();

    if (projectError) throw projectError;
    const projectId = project.id;

    // 2. Upload audio files and insert tracks
    const trackPromises = tracks.map(async (track, index) => {
      let finalAudioUrl = track.url;

      // Only upload if there's a blob (new recording)
      if (track.blob) {
        const filePath = `${user.id}/${projectId}/track-${index}-${Date.now()}.webm`;
        
        const { error: uploadError } = await supabase.storage
          .from('audio_tracks')
          .upload(filePath, track.blob, {
            contentType: 'audio/webm',
            upsert: true
          });

        if (uploadError) throw uploadError;

        const { data: publicUrlData } = supabase.storage
          .from('audio_tracks')
          .getPublicUrl(filePath);
        
        finalAudioUrl = publicUrlData.publicUrl;
      }

      // Insert track row
      return supabase
        .from('tracks')
        .insert({
          project_id: projectId,
          name: track.name,
          audio_url: finalAudioUrl,
          volume: track.volume,
          is_muted: track.isMuted,
          color: track.color,
          effects: track.effects // Assuming this column exists or will be added
        });
    });

    await Promise.all(trackPromises);
    
    return projectId;
  } catch (error: any) {
    console.error('Error saving project:', error);
    throw new Error(error.message || 'Failed to save project');
  }
}

export async function loadProject(projectId: string): Promise<{ title: string, tracks: any[] }> {
  try {
    // 1. Fetch project metadata
    const { data: project, error: projectError } = await supabase
      .from('projects')
      .select('title')
      .eq('id', projectId)
      .single();

    if (projectError) throw projectError;

    // 2. Fetch tracks
    const { data: tracks, error: tracksError } = await supabase
      .from('tracks')
      .select('*')
      .eq('project_id', projectId)
      .order('created_at', { ascending: true });

    if (tracksError) throw tracksError;

    // Map database fields to application state
    const mappedTracks = tracks.map(t => ({
      id: t.id,
      name: t.name,
      url: t.audio_url,
      color: t.color || '#d946ef',
      isMuted: t.is_muted,
      isArmed: false,
      volume: t.volume || 1,
      effects: t.effects || { delay: 0, reverb: 0 }
      // We don't have the blob easily available for remote tracks
      // but Wavesurfer can load from URL
    }));

    return {
      title: project.title,
      tracks: mappedTracks
    };
  } catch (error: any) {
    console.error('Error loading project:', error);
    throw new Error(error.message || 'Failed to load project');
  }
}
