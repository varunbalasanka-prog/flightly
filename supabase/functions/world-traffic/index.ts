import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { json } from '../_shared/http.ts'
import {
  adminClient,
  ageMs,
  publicUrl,
  publish,
  readMeta,
  releaseLock,
  tryLock,
} from '../_shared/world_cache.ts'

/**
 * Every aircraft currently broadcasting, worldwide.
 *
 * OpenSky's /states/all is the only keyless source for the whole planet at
 * once (~13,000 aircraft). It costs 4 credits a call: anonymous access gets
 * 400 credits a day, a free OpenSky account 4,000. So the snapshot is shared
 * across all users and refreshed no faster than the credit budget allows:
 *
 *   with OPENSKY_CLIENT_ID/SECRET set  -> at most every 90 seconds
 *   anonymous                          -> at most every 15 minutes
 *
 * The client is told the snapshot's age and must display it; nothing here
 * pretends a 15-minute-old picture is live.
 *
 * OpenSky throttles anonymous requests from cloud hosting IPs: from this
 * function an anonymous /states/all simply hangs. Native apps therefore fetch
 * the worldwide feed directly from the device, and this shared snapshot is
 * the web build's path, which in practice needs OpenSky credentials. After a
 * failure the function reports "unavailable" immediately for a cool-down
 * period rather than making every caller wait out another timeout.
 */

const KEY = 'world-traffic'
const FAILURE_KEY = 'world-traffic-failure'
const FAILURE_COOLDOWN_MS = 10 * 60_000
const OBJECT = 'traffic.json'
const STATES_URL = 'https://opensky-network.org/api/states/all?extended=1'
const TOKEN_URL =
  'https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token'

function hasCredentials() {
  return !!(Deno.env.get('OPENSKY_CLIENT_ID') && Deno.env.get('OPENSKY_CLIENT_SECRET'))
}

async function openSkyToken(): Promise<string | null> {
  if (!hasCredentials()) return null
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: Deno.env.get('OPENSKY_CLIENT_ID')!,
      client_secret: Deno.env.get('OPENSKY_CLIENT_SECRET')!,
    }),
    signal: AbortSignal.timeout(15_000),
  })
  if (!res.ok) {
    console.error('OpenSky token request failed:', res.status)
    return null
  }
  return (await res.json()).access_token ?? null
}

const round = (v: unknown, digits: number) =>
  typeof v === 'number' && Number.isFinite(v) ? Number(v.toFixed(digits)) : null

/**
 * Compact row: [hex, callsign, lat, lon, baroAltM, trackDeg, velocityMs,
 * onGround(0|1), verticalRateMs, category, lastContactEpoch]
 */
function compact(states: unknown[][]) {
  const rows: unknown[] = []
  for (const s of states) {
    const lon = round(s[5], 3)
    const lat = round(s[6], 3)
    if (lat === null || lon === null) continue
    rows.push([
      s[0],
      typeof s[1] === 'string' ? s[1].trim() : '',
      lat,
      lon,
      round(s[7], 0),
      round(s[10], 0),
      round(s[9], 0),
      s[8] ? 1 : 0,
      round(s[11], 1),
      typeof s[17] === 'number' ? s[17] : null,
      typeof s[4] === 'number' ? s[4] : null,
    ])
  }
  return rows
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const db = adminClient()
  const ttlMs = hasCredentials() ? 90_000 : 15 * 60_000

  try {
    const meta = await readMeta(db, KEY)
    const describe = (refreshing: boolean) => ({
      available: meta?.fetched_at != null,
      url: publicUrl(OBJECT),
      fetchedAt: meta?.fetched_at ?? null,
      aircraft: meta?.item_count ?? 0,
      refreshIntervalSeconds: ttlMs / 1000,
      authenticated: hasCredentials(),
      refreshing,
    })

    if (ageMs(meta) < ttlMs) return json(describe(false))

    const failure = await readMeta(db, FAILURE_KEY)
    if (ageMs(failure) < FAILURE_COOLDOWN_MS) {
      return json({ ...describe(false), reason: failure?.source })
    }

    // Someone else is already refreshing: hand back the current snapshot.
    if (!(await tryLock(db, KEY, 60))) return json(describe(true))

    const recordFailure = async (reason: string) => {
      await releaseLock(db, KEY)
      await db.from('world_cache_meta').upsert({
        key: FAILURE_KEY,
        fetched_at: new Date().toISOString(),
        source: reason,
        refreshing_until: null,
      })
    }

    try {
      const token = await openSkyToken()
      const res = await fetch(STATES_URL, {
        headers: {
          'Accept-Encoding': 'gzip',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        signal: AbortSignal.timeout(40_000),
      })

      if (!res.ok) {
        console.error('OpenSky states/all returned', res.status)
        await recordFailure(`opensky-http-${res.status}`)
        return json({ ...describe(false), reason: `opensky-http-${res.status}` })
      }

      const body = await res.json()
      const rows = compact(Array.isArray(body?.states) ? body.states : [])
      const fetchedAt = new Date().toISOString()

      await publish(
        db,
        KEY,
        OBJECT,
        { fetchedAt, source: 'OpenSky Network', aircraft: rows },
        rows.length,
        'opensky',
        Math.round(ttlMs / 1000),
      )

      return json({
        available: true,
        url: publicUrl(OBJECT),
        fetchedAt,
        aircraft: rows.length,
        refreshIntervalSeconds: ttlMs / 1000,
        authenticated: hasCredentials(),
        refreshing: false,
      })
    } catch (e) {
      console.error('OpenSky fetch failed:', e)
      const reason = hasCredentials() ? 'opensky-unreachable' : 'opensky-blocks-anonymous-cloud-requests'
      await recordFailure(reason)
      return json({ ...describe(false), reason })
    }
  } catch (e) {
    console.error('world-traffic error:', e)
    return json({ error: 'Could not load world traffic' }, 500)
  }
})
