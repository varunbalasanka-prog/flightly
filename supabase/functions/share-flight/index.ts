import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { flightId } = await req.json()
    if (!flightId) {
      return new Response(JSON.stringify({ error: 'Flight ID is required' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )
    
    const { data: { user } } = await supabaseClient.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      })
    }

    // Verify ownership
    const { data: flight, error: flightError } = await supabaseClient
      .from('flights')
      .select('user_id')
      .eq('id', flightId)
      .single();

    if (flightError || flight?.user_id !== user.id) {
      return new Response(JSON.stringify({ error: 'Flight not found or not owned by user' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 403,
      })
    }

    // Generate random 6-char alphanumeric code
    const inviteCode = Math.random().toString(36).substring(2, 8).toUpperCase();

    const { error: shareError } = await supabaseClient
      .from('flight_shares')
      .insert({
        flight_id: flightId,
        owner_id: user.id,
        invite_code: inviteCode,
      });

    if (shareError) throw shareError;

    return new Response(JSON.stringify({ inviteCode }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    console.error('share-flight error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
