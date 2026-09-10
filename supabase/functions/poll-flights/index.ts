import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { 
  checkGlobalQuota, 
  incrementGlobalQuota, 
  fetchFlightFromAviationstack, 
  normalizeAviationstackData 
} from '../_shared/aviationstack.ts'

serve(async (req) => {
  // This endpoint should be protected, e.g., by checking a secret CRON_KEY
  const authHeader = req.headers.get('Authorization')
  const cronKey = Deno.env.get('CRON_SECRET_KEY')
  
  if (authHeader !== `Bearer ${cronKey}`) {
    return new Response('Unauthorized', { status: 401 })
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 1. Get all active monitored flights that need polling
    const { data: monitors, error: monitorError } = await supabaseAdmin
      .from('monitored_flights')
      .select('id, flight_id, flights(flight_number, status, dep_delay_minutes), user_id')
      .eq('is_active', true)
      .order('last_polled_at', { ascending: true, nullsFirst: true })
      .limit(10); // Process in small batches to respect execution time limits

    if (monitorError) throw monitorError;
    if (!monitors || monitors.length === 0) {
      return new Response('No active monitors', { status: 200 })
    }

    let polledCount = 0;

    for (const monitor of monitors) {
      // 2. Check quota per flight
      const canMakeRequest = await checkGlobalQuota(supabaseAdmin);
      if (!canMakeRequest) {
        console.warn('Global quota exceeded during poll');
        break; 
      }

      const flightNumber = Array.isArray(monitor.flights) 
          ? monitor.flights[0].flight_number 
          : (monitor.flights as any).flight_number;
      
      const prevStatus = Array.isArray(monitor.flights)
          ? monitor.flights[0].status
          : (monitor.flights as any).status;

      const prevDelay = Array.isArray(monitor.flights)
          ? monitor.flights[0].dep_delay_minutes
          : (monitor.flights as any).dep_delay_minutes;

      // 3. Fetch from Aviationstack
      try {
        const apiResponse = await fetchFlightFromAviationstack(flightNumber);
        
        if (apiResponse.data && apiResponse.data.length > 0) {
          const rawFlight = apiResponse.data[0];
          const normalized = normalizeAviationstackData(rawFlight);

          await incrementGlobalQuota(supabaseAdmin);
          polledCount++;

          // 4. Update the flights table
          await supabaseAdmin
            .from('flights')
            .update({
              status: normalized.status,
              dep_delay_minutes: normalized.dep_delay_minutes,
              arr_delay_minutes: normalized.arr_delay_minutes,
              dep_gate: normalized.dep_gate,
              arr_gate: normalized.arr_gate,
              dep_terminal: normalized.dep_terminal,
              arr_terminal: normalized.arr_terminal,
              baggage_claim: normalized.baggage_claim,
              estimated_departure: normalized.estimated_departure,
              estimated_arrival: normalized.estimated_arrival,
              actual_departure: normalized.actual_departure,
              actual_arrival: normalized.actual_arrival,
              aircraft: normalized.aircraft,
              last_updated: new Date().toISOString(),
            })
            .eq('id', monitor.flight_id);

          // 5. Insert status snapshot
          await supabaseAdmin
            .from('status_snapshots')
            .insert({
              flight_id: monitor.flight_id,
              status: normalized.status,
              dep_delay_minutes: normalized.dep_delay_minutes,
              arr_delay_minutes: normalized.arr_delay_minutes,
              dep_gate: normalized.dep_gate,
              arr_gate: normalized.arr_gate,
              dep_terminal: normalized.dep_terminal,
              arr_terminal: normalized.arr_terminal,
              baggage_claim: normalized.baggage_claim,
              estimated_departure: normalized.estimated_departure,
              estimated_arrival: normalized.estimated_arrival,
              actual_departure: normalized.actual_departure,
              actual_arrival: normalized.actual_arrival,
            });

          // 6. Check for notifications (e.g. status change or new delay)
          if (prevStatus !== normalized.status || 
             (normalized.dep_delay_minutes && normalized.dep_delay_minutes > (prevDelay ?? 0) + 15)) {
             
             await supabaseAdmin.from('notification_events').insert({
               user_id: monitor.user_id,
               flight_id: monitor.flight_id,
               event_type: 'status_update',
               title: `Update: ${flightNumber}`,
               body: `Status is now ${normalized.status}${normalized.dep_delay_minutes ? ` (Delayed ${normalized.dep_delay_minutes}m)` : ''}`,
             });
          }

          // 7. Update monitor metadata
          // If landed or cancelled, stop monitoring
          const isTerminal = ['landed', 'cancelled', 'diverted'].includes(normalized.status);
          await supabaseAdmin
            .from('monitored_flights')
            .update({
              last_polled_at: new Date().toISOString(),
              is_active: !isTerminal,
              poll_count: (monitor.poll_count || 0) + 1
            })
            .eq('id', monitor.id);
            
        }
      } catch (err) {
        console.error(`Error polling flight ${flightNumber}:`, err);
      }
    }

    return new Response(JSON.stringify({ success: true, polledCount }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    console.error('poll-flights error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
    })
  }
})
