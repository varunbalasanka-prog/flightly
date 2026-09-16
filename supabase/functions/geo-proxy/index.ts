import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { fetchCapped, json } from '../_shared/http.ts'

/**
 * Allowlisted proxy for public data sources that either send no CORS headers
 * (so browsers block them) or need a polite, cached, identified client.
 *
 * The caller names a `source` and passes parameters; the upstream URL is built
 * here from a fixed template after validating every parameter. There is no
 * way to make this function fetch an arbitrary URL.
 *
 * Native builds call most of these upstreams directly; the web build and the
 * rate-limited or non-JSON sources (Overpass, news RSS) go through here.
 */

type Params = Record<string, unknown>
type Route = {
  ttlMs: number
  build: (p: Params) => string | { urls: string[]; body?: string }
  /** Converts a non-JSON upstream body (e.g. RSS) into a JSON-serialisable value. */
  transform?: (body: string) => unknown
}

const decodeEntities = (s: string) =>
  s.replace(/<!\[CDATA\[(.*?)\]\]>/gs, '$1')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'")

/** Minimal RSS 2.0 item extraction: title, link, source, published date. */
function parseRss(xml: string) {
  const items = [...xml.matchAll(/<item>([\s\S]*?)<\/item>/g)].slice(0, 20)
  const pick = (block: string, tag: string) =>
    // Built from a string, so the character-class escapes must be doubled.
    decodeEntities((new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`).exec(block)?.[1] ?? '').trim())
  return {
    articles: items.map(([, block]) => {
      const source = pick(block, 'source')
      let title = pick(block, 'title')
      // Google News appends " - Source" to titles.
      if (source && title.endsWith(` - ${source}`)) title = title.slice(0, -(source.length + 3))
      return { title, url: pick(block, 'link'), source, published: pick(block, 'pubDate') }
    }),
  }
}

const ICAO_LIST = /^[A-Z0-9]{4}(,[A-Z0-9]{4}){0,19}$/
const HEX = /^[0-9a-f]{6}$/
const CALLSIGN = /^[A-Z0-9]{2,12}$/
const REGISTRATION = /^[A-Z0-9-]{2,10}$/
const NEWS_QUERY = /^[\p{L}\p{N} .,'-]{2,80}$/u

function num(v: unknown, min: number, max: number, name: string): number {
  const n = typeof v === 'number' ? v : Number(v)
  if (!Number.isFinite(n) || n < min || n > max) {
    throw new BadRequest(`${name} must be a number between ${min} and ${max}`)
  }
  return n
}

function str(v: unknown, pattern: RegExp, name: string, transform = (s: string) => s) {
  const s = transform(String(v ?? '').trim())
  if (!pattern.test(s)) throw new BadRequest(`${name} is invalid`)
  return s
}

class BadRequest extends Error {}

const OVERPASS_MIRRORS = [
  'https://overpass-api.de/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
]

const ROUTES: Record<string, Route> = {
  // Airport weather observations (METAR). aviationweather.gov sends no CORS.
  metar: {
    ttlMs: 5 * 60_000,
    build: (p) => {
      const ids = str(p.ids, ICAO_LIST, 'ids', (s) => s.toUpperCase())
      return `https://aviationweather.gov/api/data/metar?ids=${ids}&format=json&hours=2`
    },
  },

  // Terminal forecasts, for "will weather be bad when I land".
  taf: {
    ttlMs: 30 * 60_000,
    build: (p) => {
      const ids = str(p.ids, ICAO_LIST, 'ids', (s) => s.toUpperCase())
      return `https://aviationweather.gov/api/data/taf?ids=${ids}&format=json`
    },
  },

  // ~24h of real recorded positions for one aircraft (adsb.lol, ODbL).
  'adsb-trace': {
    ttlMs: 60_000,
    build: (p) => {
      const hex = str(p.hex, HEX, 'hex', (s) => s.toLowerCase())
      return `https://adsb.lol/data/traces/${hex.slice(-2)}/trace_full_${hex}.json`
    },
  },

  // All aircraft currently broadcasting as military.
  'adsb-mil': {
    ttlMs: 20_000,
    build: () => 'https://api.adsb.lol/v2/mil',
  },

  'adsb-radius': {
    ttlMs: 10_000,
    build: (p) => {
      const lat = num(p.lat, -90, 90, 'lat').toFixed(4)
      const lon = num(p.lon, -180, 180, 'lon').toFixed(4)
      const dist = Math.round(num(p.dist, 1, 250, 'dist'))
      return `https://api.adsb.lol/v2/lat/${lat}/lon/${lon}/dist/${dist}`
    },
  },

  'adsb-callsign': {
    ttlMs: 15_000,
    build: (p) => {
      const cs = str(p.callsign, CALLSIGN, 'callsign', (s) => s.toUpperCase())
      return `https://api.adsb.lol/v2/callsign/${cs}`
    },
  },

  // Look an airframe up by tail number, for "where's my plane".
  'adsb-reg': {
    ttlMs: 15_000,
    build: (p) => {
      const reg = str(p.reg, REGISTRATION, 'reg', (s) => s.toUpperCase())
      return `https://api.adsb.lol/v2/reg/${reg}`
    },
  },

  // Mapped military installations inside a bounding box (OpenStreetMap).
  // Bounded to keep queries cheap for a volunteer-run service.
  'military-installations': {
    ttlMs: 6 * 60 * 60_000,
    build: (p) => {
      const s = num(p.south, -90, 90, 'south')
      const w = num(p.west, -180, 180, 'west')
      const n = num(p.north, -90, 90, 'north')
      const e = num(p.east, -180, 180, 'east')
      if (n <= s || e <= w) throw new BadRequest('bbox is inverted')
      if ((n - s) * (e - w) > 64) throw new BadRequest('bbox too large; zoom in')
      const bbox = `${s.toFixed(3)},${w.toFixed(3)},${n.toFixed(3)},${e.toFixed(3)}`
      const query =
        `[out:json][timeout:25];(` +
        `way["landuse"="military"](${bbox});` +
        `relation["landuse"="military"](${bbox});` +
        `way["military"~"airfield|base|naval_base|barracks|range"](${bbox});` +
        `relation["military"~"airfield|base|naval_base|barracks|range"](${bbox});` +
        `node["military"~"airfield|base|naval_base|barracks"](${bbox});` +
        `);out center tags 400;`
      return { urls: OVERPASS_MIRRORS, body: `data=${encodeURIComponent(query)}` }
    },
  },

  // Recent news mentioning a place. GDELT rate-limits shared cloud IPs so
  // aggressively that it is unusable from here; Google News RSS is parsed
  // server-side into JSON instead.
  news: {
    ttlMs: 20 * 60_000,
    build: (p) => {
      const q = encodeURIComponent(str(p.query, NEWS_QUERY, 'query'))
      return `https://news.google.com/rss/search?q=${q}&hl=en-US&gl=US&ceid=US:en`
    },
    transform: parseRss,
  },
}

type CacheEntry = { at: number; status: number; body: string }
const cache = new Map<string, CacheEntry>()

function cacheKey(source: string, params: Params) {
  return `${source}:${JSON.stringify(params, Object.keys(params).sort())}`
}

async function fetchRoute(route: Route, params: Params) {
  const target = route.build(params)
  if (typeof target === 'string') return fetchCapped(target, { timeoutMs: 20_000 })

  let lastError: unknown
  for (const url of target.urls) {
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'User-Agent': 'SkyPulse/0.1 (+https://github.com/varunbalasanka-prog/flightly)',
          'Content-Type': 'application/x-www-form-urlencoded',
          Accept: 'application/json',
        },
        body: target.body,
        signal: AbortSignal.timeout(35_000),
      })
      if (res.ok) return { status: 200, body: await res.text() }
      lastError = new Error(`mirror ${url} returned ${res.status}`)
    } catch (e) {
      lastError = e
    }
  }
  throw lastError
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const body = await req.json().catch(() => ({}))
    const source = String(body?.source ?? '')
    const params: Params = body?.params && typeof body.params === 'object' ? body.params : {}

    const route = ROUTES[source]
    if (!route) return json({ error: 'Unknown source' }, 400)

    const key = cacheKey(source, params)
    const hit = cache.get(key)
    if (hit && Date.now() - hit.at < route.ttlMs) {
      return json(hit.body, hit.status, { 'X-Cache': 'HIT' })
    }

    let result: { status: number; body: string }
    try {
      result = await fetchRoute(route, params)
    } catch (e) {
      if (e instanceof BadRequest) throw e
      // Serve stale rather than nothing when an upstream stumbles.
      if (hit) return json(hit.body, hit.status, { 'X-Cache': 'STALE' })
      console.error(`geo-proxy ${source} failed:`, e)
      return json({ error: 'Upstream unavailable' }, 502)
    }

    // Upstreams answer rate limiting with plain text; don't cache or forward it
    // as if it were data.
    if (result.status === 404) return json({ notFound: true }, 200)
    if (result.status === 200 && route.transform) {
      try {
        result = { status: 200, body: JSON.stringify(route.transform(result.body)) }
      } catch (e) {
        console.error(`geo-proxy ${source} transform failed:`, e)
        result = { status: 502, body: '' }
      }
    }
    const looksJson = /^\s*[\[{]/.test(result.body)
    if (result.status !== 200 || !looksJson) {
      if (hit) return json(hit.body, hit.status, { 'X-Cache': 'STALE' })
      return json({ error: 'Upstream unavailable', upstreamStatus: result.status }, 502)
    }

    cache.set(key, { at: Date.now(), status: 200, body: result.body })
    if (cache.size > 300) cache.delete(cache.keys().next().value!)

    return json(result.body, 200, { 'X-Cache': 'MISS' })
  } catch (e) {
    if (e instanceof BadRequest) return json({ error: e.message }, 400)
    console.error('geo-proxy error:', e)
    return json({ error: 'Proxy failed' }, 500)
  }
})
