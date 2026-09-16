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

    // Math.random() is not a CSPRNG and its base-36 expansion can yield fewer
    // than 6 characters, so invite codes were both guessable and occasionally
    // short. Use crypto randomness over an unambiguous alphabet (no O/0/I/1).
    const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    const generateInviteCode = () => {
      const bytes = new Uint8Array(8); // must match AppConfig.inviteCodeLength
      crypto.getRandomValues(bytes);
      return Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join('');
    };
    // invite_code is UNIQUE, so a collision surfaced as a 500. Retry a few
    // times before giving up (32^8 makes this vanishingly unlikely anyway).
    let inviteCode = '';
    let inserted = false;

    for (let attempt = 0; attempt < 5 && !inserted; attempt++) {
      inviteCode = generateInviteCode();
      const { error: shareError } = await supabaseClient
        .from('flight_shares')
        .insert({
          flight_id: flightId,
          owner_id: user.id,
          invite_code: inviteCode,
        });

      if (!shareError) {
        inserted = true;
      } else if (shareError.code !== '23505') {
        throw shareError; // not a uniqueness violation
      }
    }

    if (!inserted) {
      return new Response(JSON.stringify({ error: 'Could not create a share code' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 503,
      })
    }

    return new Response(JSON.stringify({ inviteCode }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    // Log detail server-side; don't hand internals to the client.
    console.error('share-flight error:', error)
    return new Response(JSON.stringify({ error: 'Could not create a share code' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
