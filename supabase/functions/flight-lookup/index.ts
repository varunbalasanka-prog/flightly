import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { 
  checkGlobalQuota, 
  incrementGlobalQuota, 
  fetchFlightFromAviationstack, 
  normalizeAviationstackData 
} from '../_shared/aviationstack.ts'

serve(async (req) => {
  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // The Flutter client posts { flight_number }. This handler used to accept
    // only { flightIata }, so every real lookup returned 400 and the client
    // silently fell through to its offline fallback -- the live data path was
    // never actually exercised. Accept both spellings.
    const body = await req.json()
    const flightIata = body.flight_number ?? body.flightIata
    if (!flightIata) {
      return new Response(JSON.stringify({ error: 'Flight IATA is required' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // Initialize Supabase client using auth header from client
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

    // Initialize a service role client to bypass RLS for quota checks
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const canMakeRequest = await checkGlobalQuota(supabaseAdmin);
    if (!canMakeRequest) {
      return new Response(JSON.stringify({ error: 'Global API quota exceeded' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 429,
      })
    }

    // Fetch from API
    const apiResponse = await fetchFlightFromAviationstack(flightIata);
    if (!apiResponse.data || apiResponse.data.length === 0) {
      return new Response(JSON.stringify({ error: 'Flight not found' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 404,
      })
    }

    // Increment quota
    await incrementGlobalQuota(supabaseAdmin);

    // Grab the first match and normalize it
    const rawFlight = apiResponse.data[0];
    const normalizedData = normalizeAviationstackData(rawFlight);

    // Return the data back to client. 
    // The client will be responsible for creating the trip/flight record if they want to save it.
    // Or we could insert it here. For lookup, we just return the data.
    // Shape must match what the client parses: { flights: [...], source }.
    return new Response(JSON.stringify({
      flights: [normalizedData],
      source: 'aviationstack',
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    // Log the detail server-side; don't hand internal messages to the client.
    console.error('flight-lookup error:', error)
    return new Response(JSON.stringify({ error: 'Flight lookup failed' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
