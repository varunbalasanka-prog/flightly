import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { 
  checkGlobalQuota, 
  incrementGlobalQuota, 
  fetchFlightFromAviationstack, 
  normalizeAviationstackData 
} from '../_shared/aviationstack.ts'

serve(async (req) => {
  // Only the pg_cron job may invoke this. If CRON_SECRET_KEY is not
  // configured the comparison used to become `Bearer undefined`, which an
  // attacker could send verbatim to trigger unlimited polling and drain the
  // provider quota. Fail closed instead.
  const cronKey = Deno.env.get('CRON_SECRET_KEY')
  if (!cronKey) {
    console.error('CRON_SECRET_KEY is not configured; refusing to run.')
    return new Response('Unauthorized', { status: 401 })
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader || !timingSafeEqual(authHeader, `Bearer ${cronKey}`)) {
    return new Response('Unauthorized', { status: 401 })
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 1. Get active monitors, freshest-last so nothing starves.
    const { data: monitors, error: monitorError } = await supabaseAdmin
      .from('monitored_flights')
      .select(
        'id, flight_id, poll_count, last_polled_at, user_id, ' +
        'flights(flight_number, status, dep_delay_minutes, scheduled_departure, scheduled_arrival)',
      )
      .eq('is_active', true)
      .order('last_polled_at', { ascending: true, nullsFirst: true })
      .limit(10); // Process in small batches to respect execution time limits

    if (monitorError) throw monitorError;
    if (!monitors || monitors.length === 0) {
      return new Response('No active monitors', { status: 200 })
    }

    let polledCount = 0;
    let skippedCount = 0;
    let retiredCount = 0;

    for (const monitor of monitors) {
      const flightRow: any = Array.isArray(monitor.flights)
        ? monitor.flights[0]
        : monitor.flights;

      // 2. Retire monitors whose flight is well past its arrival. Without this
      // a flight the provider never returns data for stays active forever and
      // keeps consuming a monitoring slot.
      const arrival = flightRow?.scheduled_arrival
        ? new Date(flightRow.scheduled_arrival).getTime()
        : null;
      if (arrival !== null && !Number.isNaN(arrival) &&
          Date.now() > arrival + 6 * 60 * 60_000) {
        await supabaseAdmin
          .from('monitored_flights')
          .update({ is_active: false, last_polled_at: new Date().toISOString() })
          .eq('id', monitor.id);
        retiredCount++;
        continue;
      }

      // 3. Respect the polling window. AppConfig budgets 100 requests a MONTH
      // globally, while a 15-minute cron is 96 requests a DAY -- polling every
      // active monitor on every tick burned the entire quota in about a day.
      // Only spend a request when the flight is actually close to moving.
      const dueAt = nextPollDue(monitor.last_polled_at, flightRow);
      if (dueAt > Date.now()) {
        skippedCount++;
        continue;
      }

      // 4. Check quota before spending a request.
      const canMakeRequest = await checkGlobalQuota(supabaseAdmin);
      if (!canMakeRequest) {
        console.warn('Global quota exceeded during poll');
        break; 
      }

      const flightNumber = flightRow?.flight_number;
      const prevStatus = flightRow?.status;
      const prevDelay = flightRow?.dep_delay_minutes;

      // 5. Fetch from Aviationstack
      try {
        const apiResponse = await fetchFlightFromAviationstack(flightNumber);
        
        if (apiResponse.data && apiResponse.data.length > 0) {
          const rawFlight = apiResponse.data[0];
          const normalized = normalizeAviationstackData(rawFlight);

          await incrementGlobalQuota(supabaseAdmin);
          polledCount++;

          // 6. Update the flights table
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

          // 7. Insert status snapshot
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

          // 8. Check for notifications (e.g. status change or new delay)
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

          // 9. Update monitor metadata
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
            
        } else {
          // No data for this flight. Still stamp last_polled_at, otherwise this
          // monitor sorts first on every subsequent run (nullsFirst) and
          // starves every other flight in the queue indefinitely.
          await supabaseAdmin
            .from('monitored_flights')
            .update({
              last_polled_at: new Date().toISOString(),
              poll_count: (monitor.poll_count || 0) + 1,
            })
            .eq('id', monitor.id);
        }
      } catch (err) {
        console.error(`Error polling flight ${flightNumber}:`, err);
        // A failing flight must also advance, for the same reason.
        await supabaseAdmin
          .from('monitored_flights')
          .update({ last_polled_at: new Date().toISOString() })
          .eq('id', monitor.id);
      }
    }

    return new Response(JSON.stringify({ success: true, polledCount, skippedCount, retiredCount }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    console.error('poll-flights error:', error)
    return new Response(JSON.stringify({ error: 'Poll failed' }), {
      status: 500,
    })
  }
})

/** Minutes between polls, widening the further a flight is from departure. */
function pollIntervalMinutes(minutesToDeparture: number): number {
  // In the air / just departed: the window where gate, baggage and arrival
  // times actually change.
  if (minutesToDeparture <= 0) return 15;
  // Final approach to departure: gate changes cluster here.
  if (minutesToDeparture <= 120) return 15;
  if (minutesToDeparture <= 360) return 60;
  if (minutesToDeparture <= 1440) return 240;
  // More than a day out, a schedule barely moves; once every 12h is plenty.
  return 720;
}

/** Epoch millis at which this monitor next deserves an API request. */
function nextPollDue(lastPolledAt: string | null, flightRow: any): number {
  const now = Date.now();
  if (!lastPolledAt) return 0; // never polled -- go now

  const last = new Date(lastPolledAt).getTime();
  const departure = flightRow?.scheduled_departure
    ? new Date(flightRow.scheduled_departure).getTime()
    : null;

  // Without a departure time we cannot reason about the window; fall back to
  // the base cadence rather than hammering or stalling.
  if (departure === null || Number.isNaN(departure)) {
    return last + 15 * 60_000;
  }

  const minutesToDeparture = (departure - now) / 60_000;
  return last + pollIntervalMinutes(minutesToDeparture) * 60_000;
}

/** Length-independent comparison, so the secret cannot be recovered by timing. */
function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const aBytes = encoder.encode(a);
  const bBytes = encoder.encode(b);
  if (aBytes.length !== bBytes.length) return false;
  let diff = 0;
  for (let i = 0; i < aBytes.length; i++) diff |= aBytes[i] ^ bBytes[i];
  return diff === 0;
}
