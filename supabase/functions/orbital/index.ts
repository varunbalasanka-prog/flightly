import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import * as satellite from 'npm:satellite.js@6.0.1'
import { corsHeaders } from '../_shared/cors.ts'
import { fetchCapped, json } from '../_shared/http.ts'
import { adminClient, ageMs, readMeta, releaseLock, tryLock, BUCKET } from '../_shared/world_cache.ts'

/**
 * Satellite positions right now, plus the next ISS pass over a point.
 *
 * Orbital elements come from CelesTrak, which asks clients not to download a
 * group more than once every two hours. CelesTrak also rate-limits the shared
 * cloud IPs this function runs on, so the app downloads elements itself (they
 * are CORS-enabled) and sends them here; the function only does the SGP4 maths
 * (satellite.js). The server-side fetch below is a fallback for callers that
 * send no elements. The next-pass search follows God's Eye View's issPass.js
 * (MIT), itself after skylight (MIT).
 */

const GROUPS = new Set(['stations', 'visual', 'weather', 'gps-ops', 'starlink'])
const ELEMENT_TTL_MS = 2 * 60 * 60_000
const R2D = 180 / Math.PI
const D2R = Math.PI / 180

type Gp = { OBJECT_NAME: string; NORAD_CAT_ID: number; [k: string]: unknown }

async function elements(group: string): Promise<Gp[]> {
  const db = adminClient()
  const key = `tle-${group}`
  const object = `${key}.json`
  const meta = await readMeta(db, key)

  if (ageMs(meta) < ELEMENT_TTL_MS || !(await tryLock(db, key, 120))) {
    const { data } = await db.storage.from(BUCKET).download(object)
    if (data) return JSON.parse(await data.text())
  }

  try {
    const { status, body } = await fetchCapped(
      `https://celestrak.org/NORAD/elements/gp.php?GROUP=${group}&FORMAT=json`,
      { timeoutMs: 30_000, maxBytes: 30 * 1024 * 1024 },
    )
    if (status !== 200 || !body.trim().startsWith('[')) throw new Error(`CelesTrak ${status}`)
    const gps: Gp[] = JSON.parse(body)
    await db.storage.from(BUCKET).upload(object, new Blob([body], { type: 'application/json' }), {
      upsert: true,
      contentType: 'application/json',
    })
    await db.from('world_cache_meta').upsert({
      key,
      fetched_at: new Date().toISOString(),
      item_count: gps.length,
      source: 'celestrak',
      refreshing_until: null,
    })
    return gps
  } catch (e) {
    await releaseLock(db, key)
    const { data } = await db.storage.from(BUCKET).download(object)
    if (data) return JSON.parse(await data.text())
    throw e
  }
}

function lookAngles(satrec: satellite.SatRec, when: Date, lat: number, lon: number) {
  const pv = satellite.propagate(satrec, when)
  if (!pv || !pv.position || typeof pv.position === 'boolean') return null
  const ecf = satellite.eciToEcf(pv.position, satellite.gstime(when))
  const look = satellite.ecfToLookAngles({ latitude: lat * D2R, longitude: lon * D2R, height: 0 }, ecf)
  return { elevDeg: look.elevation * R2D, azDeg: ((look.azimuth * R2D) % 360 + 360) % 360 }
}

/** Coarse 30s scan over 24h, refined to ~5s at the rise and set. */
function nextPass(satrec: satellite.SatRec, lat: number, lon: number, minElevDeg = 10) {
  const start = Date.now()
  const horizon = start + 24 * 3600_000
  const above = (t: number) => (lookAngles(satrec, new Date(t), lat, lon)?.elevDeg ?? -90) >= minElevDeg

  for (let t = start; t < horizon; t += 30_000) {
    if (!above(t)) continue
    let rise = t
    for (let r = t - 30_000; r < t; r += 5_000) if (above(r)) { rise = r; break }
    let set = t, peak = { elevDeg: -90, azDeg: 0, at: t }
    for (let s = t; s < horizon; s += 5_000) {
      const la = lookAngles(satrec, new Date(s), lat, lon)
      if (!la || la.elevDeg < minElevDeg) { set = s; break }
      if (la.elevDeg > peak.elevDeg) peak = { ...la, at: s }
    }
    return {
      rise: new Date(rise).toISOString(),
      set: new Date(set).toISOString(),
      peak: new Date(peak.at).toISOString(),
      maxElevationDeg: Number(peak.elevDeg.toFixed(1)),
      peakAzimuthDeg: Number(peak.azDeg.toFixed(0)),
    }
  }
  return null
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const body = await req.json().catch(() => ({}))
    const group = GROUPS.has(body?.group) ? body.group : 'visual'
    const now = new Date()
    const gmst = satellite.gstime(now)

    // Elements supplied by the client take priority (see header comment).
    const supplied = Array.isArray(body?.elements) ? body.elements : null
    if (supplied && supplied.length > 3000) {
      return json({ error: 'Too many element sets; 3000 max' }, 400)
    }
    const isGp = (g: any): g is Gp =>
      g && typeof g.OBJECT_NAME === 'string' && Number.isInteger(g.NORAD_CAT_ID) && typeof g.EPOCH === 'string'
    const gps: Gp[] = supplied ? supplied.filter(isGp) : await elements(group)
    const sats: unknown[] = []
    for (const gp of gps) {
      try {
        const satrec = satellite.json2satrec(gp as any)
        const pv = satellite.propagate(satrec, now)
        if (!pv || !pv.position || typeof pv.position === 'boolean') continue
        const geo = satellite.eciToGeodetic(pv.position, gmst)
        sats.push([
          gp.OBJECT_NAME,
          gp.NORAD_CAT_ID,
          Number(satellite.degreesLat(geo.latitude).toFixed(3)),
          Number(satellite.degreesLong(geo.longitude).toFixed(3)),
          Math.round(geo.height),
        ])
      } catch {
        // Decayed or malformed element set: skip it.
      }
    }

    let issPass = null
    const lat = Number(body?.lat), lon = Number(body?.lon)
    if (Number.isFinite(lat) && Number.isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180) {
      const iss = gps.find((g) => g.NORAD_CAT_ID === 25544) ??
        (supplied ? undefined : (await elements('stations')).find((g) => g.NORAD_CAT_ID === 25544))
      if (iss) issPass = nextPass(satellite.json2satrec(iss as any), lat, lon)
    }

    return json({ computedAt: now.toISOString(), group, satellites: sats, issPass })
  } catch (e) {
    console.error('orbital error:', e)
    return json({ error: 'Could not compute satellite positions' }, 500)
  }
})
