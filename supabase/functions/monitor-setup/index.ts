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

    // Use service role for quotas
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Check user quota for monitoring
    // Must be UTC month start to match `date_trunc('month', NOW())` used by the
    // quota stored procedures; setHours() here used the runtime's local zone
    // and produced a period_start that never matched an existing row.
    const now = new Date();
    const currentPeriod = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));

    const { data: userQuota, error: quotaError } = await supabaseAdmin
      .from('user_quotas')
      .select('active_monitored_count, active_monitored_limit')
      .eq('user_id', user.id)
      .eq('period_start', currentPeriod.toISOString())
      .single();

    if (quotaError && quotaError.code !== 'PGRST116') {
      throw quotaError;
    }

    const count = userQuota?.active_monitored_count ?? 0;
    const limit = userQuota?.active_monitored_limit ?? 1;

    if (count >= limit) {
      return new Response(JSON.stringify({ error: 'User monitoring quota exceeded. You can only monitor 1 active flight in the beta.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 403,
      })
    }

    // Setup monitor
    // monitored_flights has UNIQUE(flight_id, user_id), so a plain insert threw
    // a 500 whenever a user re-monitored a flight they had previously stopped.
    const { data: existing } = await supabaseAdmin
      .from('monitored_flights')
      .select('id, is_active')
      .eq('flight_id', flightId)
      .eq('user_id', user.id)
      .maybeSingle();

    if (existing?.is_active) {
      return new Response(JSON.stringify({ success: true, alreadyActive: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      })
    }

    const { error: monitorError } = await supabaseAdmin
      .from('monitored_flights')
      .upsert(
        { flight_id: flightId, user_id: user.id, is_active: true },
        { onConflict: 'flight_id,user_id' },
      );

    if (monitorError) throw monitorError;

    // Update quota
    if (!userQuota) {
      await supabaseAdmin.from('user_quotas').insert({
        user_id: user.id,
        period_start: currentPeriod.toISOString(),
        active_monitored_count: 1,
      });
    } else {
      await supabaseAdmin.from('user_quotas')
        .update({ active_monitored_count: count + 1 })
        .eq('user_id', user.id)
        .eq('period_start', currentPeriod.toISOString());
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    console.error('monitor-setup error:', error)
    return new Response(JSON.stringify({ error: 'Could not start monitoring' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
