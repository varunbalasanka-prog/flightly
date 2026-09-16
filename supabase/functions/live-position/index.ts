import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'

/**
 * CORS proxy for adsb.lol live positions.
 *
 * adsb.lol serves no Access-Control-Allow-Origin header, so a browser blocks
 * the request outright. Native builds call the API directly; the web build
 * routes through here. adsbdb does send CORS and needs no proxy.
 *
 * Also gives us a shared cache in front of a free community service, so N web
 * clients watching the same flight cost one upstream request rather than N.
 */

const UPSTREAM = 'https://api.adsb.lol/v2';
const CACHE_TTL_MS = 15_000;
const UPSTREAM_TIMEOUT_MS = 8_000;

/** Callsigns are alphanumeric; anything else is not ours to forward. */
const CALLSIGN_PATTERN = /^[A-Z0-9]{2,12}$/;

type CacheEntry = { at: number; body: string };
const cache = new Map<string, CacheEntry>();

function cached(key: string): string | null {
  const entry = cache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.at > CACHE_TTL_MS) {
    cache.delete(key);
    return null;
  }
  return entry.body;
}

function json(body: string, status = 200) {
  return new Response(body, {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  });
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // The Flutter client posts { callsign }; a query param also works for
    // manual testing.
    let requested = new URL(req.url).searchParams.get('callsign') ?? '';
    if (!requested && req.method === 'POST') {
      const body = await req.json().catch(() => ({}));
      requested = body?.callsign ?? '';
    }
    const callsign = String(requested).trim().toUpperCase();

    // Only ever forward a validated callsign to a fixed upstream path, so this
    // cannot be turned into an open proxy for arbitrary URLs.
    if (!CALLSIGN_PATTERN.test(callsign)) {
      return json(JSON.stringify({ error: 'A valid callsign is required' }), 400);
    }

    const hit = cached(callsign);
    if (hit !== null) {
      return new Response(hit, {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
          'X-Cache': 'HIT',
        },
      });
    }

    const upstream = await fetch(
      `${UPSTREAM}/callsign/${encodeURIComponent(callsign)}`,
      { signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS) },
    );

    if (!upstream.ok) {
      // 404 is a real answer: that callsign is not currently airborne.
      if (upstream.status === 404) return json(JSON.stringify({ ac: [] }));
      return json(JSON.stringify({ error: 'Upstream unavailable' }), 502);
    }

    const body = await upstream.text();
    cache.set(callsign, { at: Date.now(), body });

    // Bound the cache; this instance may be long-lived.
    if (cache.size > 500) {
      for (const key of cache.keys()) {
        cache.delete(key);
        if (cache.size <= 400) break;
      }
    }

    return new Response(body, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
        'X-Cache': 'MISS',
      },
    });
  } catch (error) {
    console.error('live-position error:', error)
    return json(JSON.stringify({ error: 'Could not fetch live position' }), 500);
  }
})
