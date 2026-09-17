import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { fetchCapped, json } from '../_shared/http.ts'
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
 * One normalized catalog of public road and weather cameras.
 *
 * These are cameras that transport agencies publish for exactly this purpose:
 * seeing road and weather conditions. Coverage is regional, not global — a
 * destination outside these areas simply has no cameras, and the app says so.
 *
 * Networks and their catalog formats follow God's Eye View (MIT) by Bilawal
 * Sidhu, verified against the live endpoints. Estonia (DATEX2 XML) and the
 * TxDOT snapshot API are not included.
 *
 * Row: [id, name, lat, lon, imageUrl, provider, region]
 */

const KEY = 'cctv-catalog'
const OBJECT = 'cctv.json'
const TTL_MS = 24 * 60 * 60_000

type Camera = [string, string, number, number, string, string, string]

const finite = (v: unknown) => {
  const n = typeof v === 'number' ? v : Number(v)
  return Number.isFinite(n) ? n : null
}

async function getJson(url: string, headers: Record<string, string> = {}) {
  const { status, body } = await fetchCapped(url, { timeoutMs: 30_000, maxBytes: 40 * 1024 * 1024, headers })
  if (status !== 200) throw new Error(`${url} -> ${status}`)
  return JSON.parse(body)
}

async function tfl(): Promise<Camera[]> {
  const places = await getJson('https://api.tfl.gov.uk/Place/Type/JamCam')
  const out: Camera[] = []
  for (const p of places ?? []) {
    const props: Record<string, string> = {}
    for (const kv of p?.additionalProperties ?? []) props[kv.key] = kv.value
    const lat = finite(p?.lat), lon = finite(p?.lon)
    const url = String(props.imageUrl ?? '')
    if (lat === null || lon === null || !url.startsWith('https://')) continue
    out.push([`tfl-${p.id}`, String(p.commonName ?? 'JamCam'), lat, lon, url, 'Transport for London', 'London'])
  }
  return out
}

async function caltrans(): Promise<Camera[]> {
  const districts = Array.from({ length: 12 }, (_, i) => i + 1)
  const results = await Promise.allSettled(
    districts.map((d) =>
      getJson(`https://cwwp2.dot.ca.gov/data/d${d}/cctv/cctvStatusD${String(d).padStart(2, '0')}.json`),
    ),
  )
  const out: Camera[] = []
  results.forEach((r, i) => {
    if (r.status !== 'fulfilled') return
    for (const row of r.value?.data ?? []) {
      const c = row?.cctv
      if (!c || c.inService === 'false' || c.inService === false) continue
      const lat = finite(c.location?.latitude), lon = finite(c.location?.longitude)
      const url = String(c.imageData?.static?.currentImageURL ?? '')
      if (lat === null || lon === null || !url.startsWith('https://cwwp2.dot.ca.gov/')) continue
      out.push([
        `caltrans-${districts[i]}-${c.index ?? c.location?.locationName}`,
        String(c.location?.locationName ?? 'Caltrans camera'),
        lat, lon, url, 'Caltrans', 'California',
      ])
    }
  })
  return out
}

async function fintraffic(): Promise<Camera[]> {
  const body = await getJson('https://tie.digitraffic.fi/api/weathercam/v1/stations', {
    'Digitraffic-User': 'SkyPulse',
  })
  const out: Camera[] = []
  for (const f of body?.features ?? []) {
    const [lon, lat] = f?.geometry?.coordinates ?? []
    if (finite(lat) === null || finite(lon) === null) continue
    const name = String(f.properties?.name ?? '').replace(/^[a-z]+\d*_/i, '').replace(/_/g, ' ')
    for (const preset of f.properties?.presets ?? []) {
      if (preset?.inCollection === false || !preset?.id) continue
      out.push([
        `fi-${preset.id}`, name || `Weather camera ${f.properties?.id}`,
        lat, lon, `https://weathercam.digitraffic.fi/${preset.id}.jpg`,
        'Fintraffic', 'Finland',
      ])
    }
  }
  return out
}

async function driveBc(): Promise<Camera[]> {
  const rows = await getJson('https://www.drivebc.ca/api/webcams/')
  const out: Camera[] = []
  for (const r of rows ?? []) {
    if (!Number.isSafeInteger(r?.id) || r.is_on === false) continue
    const [lon, lat] = r.location?.coordinates ?? []
    if (finite(lat) === null || finite(lon) === null) continue
    out.push([`bc-${r.id}`, String(r.name ?? `DriveBC ${r.id}`), lat, lon,
      `https://www.drivebc.ca/images/${r.id}.jpg`, 'DriveBC', 'British Columbia'])
  }
  return out
}

async function nsw(): Promise<Camera[]> {
  const body = await getJson('https://data.livetraffic.com/cameras/traffic-cam.json')
  const out: Camera[] = []
  for (const f of body?.features ?? []) {
    const [lon, lat] = f?.geometry?.coordinates ?? []
    const url = String(f?.properties?.href ?? '')
    if (finite(lat) === null || finite(lon) === null || !url.startsWith('https://')) continue
    out.push([`nsw-${f.id ?? f.properties?.title}`, String(f.properties?.title ?? 'NSW camera'),
      lat, lon, url, 'Transport for NSW', 'New South Wales'])
  }
  return out
}

async function ontario(): Promise<Camera[]> {
  const rows = await getJson('https://511on.ca/api/v2/get/cameras?format=json&lang=en')
  const out: Camera[] = []
  for (const r of rows ?? []) {
    const lat = finite(r?.Latitude), lon = finite(r?.Longitude)
    if (lat === null || lon === null) continue
    const view = (r.Views ?? []).find((v: any) => String(v?.Status) === 'Enabled' && v?.Url)
    if (!view) continue
    out.push([`on-${r.Id}-${view.Id}`, String(r.Location ?? 'Ontario 511 camera'),
      lat, lon, String(view.Url), 'Ontario 511', 'Ontario'])
  }
  return out
}

async function calgary(): Promise<Camera[]> {
  const rows = await getJson('https://data.calgary.ca/resource/k7p9-kppz.json?$limit=5000')
  const out: Camera[] = []
  for (const r of rows ?? []) {
    const [lon, lat] = r?.point?.coordinates ?? []
    let url = String(r?.camera_url?.url ?? '')
    if (finite(lat) === null || finite(lon) === null || !url) continue
    // The dataset lists http:// frames; the same host serves them over https.
    url = url.replace(/^http:\/\/trafficcam\.calgary\.ca\//, 'https://trafficcam.calgary.ca/')
    if (!url.startsWith('https://trafficcam.calgary.ca/')) continue
    out.push([`yyc-${url.split('/').pop()}`, String(r.camera_location ?? 'Calgary camera'),
      lat, lon, url, 'City of Calgary', 'Calgary'])
  }
  return out
}

async function austin(): Promise<Camera[]> {
  const body = await getJson('https://data.austintexas.gov/api/views/b4k4-adkb/rows.json?accessType=DOWNLOAD')
  const cols: string[] = (body?.meta?.view?.columns ?? []).map((c: any) => c.fieldName)
  const idx = (name: string) => cols.indexOf(name)
  const iId = idx('camera_id'), iStatus = idx('camera_status'), iName = idx('location_name'), iLoc = idx('location')
  const out: Camera[] = []
  for (const row of body?.data ?? []) {
    if (String(row[iStatus] ?? '').toUpperCase() !== 'TURNED_ON') continue
    const m = /POINT \((-?[\d.]+) (-?[\d.]+)\)/.exec(String(row[iLoc] ?? ''))
    if (!m) continue
    const id = String(row[iId])
    out.push([`atx-${id}`, String(row[iName] ?? `Austin camera ${id}`).trim(),
      Number(m[2]), Number(m[1]), `https://cctv.austinmobility.io/image/${encodeURIComponent(id)}.jpg`,
      'City of Austin', 'Austin'])
  }
  return out
}

const NETWORKS: Record<string, () => Promise<Camera[]>> = {
  tfl, caltrans, fintraffic, driveBc, nsw, ontario, calgary, austin,
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const db = adminClient()
  try {
    const meta = await readMeta(db, KEY)
    const current = { url: publicUrl(OBJECT), fetchedAt: meta?.fetched_at ?? null, cameras: meta?.item_count ?? 0 }

    if (ageMs(meta) < TTL_MS) return json(current)
    if (!(await tryLock(db, KEY, 300))) return json({ ...current, refreshing: true })

    try {
      const names = Object.keys(NETWORKS)
      const results = await Promise.allSettled(names.map((n) => NETWORKS[n]()))
      const cameras: Camera[] = []
      const networks: Record<string, number | string> = {}
      results.forEach((r, i) => {
        if (r.status === 'fulfilled') {
          cameras.push(...r.value)
          networks[names[i]] = r.value.length
        } else {
          networks[names[i]] = `failed: ${String(r.reason).slice(0, 80)}`
          console.error(`cctv network ${names[i]} failed:`, r.reason)
        }
      })

      if (cameras.length === 0) {
        await releaseLock(db, KEY)
        return json({ ...current, networks, error: 'All camera networks failed' }, 502)
      }

      const fetchedAt = new Date().toISOString()
      await publish(db, KEY, OBJECT, { fetchedAt, networks, cameras }, cameras.length, 'multi', 3600)
      return json({ url: publicUrl(OBJECT), fetchedAt, cameras: cameras.length, networks })
    } catch (e) {
      await releaseLock(db, KEY)
      throw e
    }
  } catch (e) {
    console.error('cctv-catalog error:', e)
    return json({ error: 'Could not load camera catalog' }, 500)
  }
})
