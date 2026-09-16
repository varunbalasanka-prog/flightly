import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

/**
 * Shared, lock-guarded snapshot cache backed by a public Storage bucket.
 *
 * Expensive global datasets (every aircraft in the world, every public camera)
 * are refreshed by exactly one caller at a time and then served to everyone as
 * a static file from the Storage CDN. Without the lock, N users opening the
 * World tab together would each hit OpenSky, burning N times the credits.
 */

export const BUCKET = 'world-cache'

export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )
}

export function publicUrl(object: string): string {
  return `${Deno.env.get('SUPABASE_URL')}/storage/v1/object/public/${BUCKET}/${object}`
}

export type CacheMeta = {
  key: string
  fetched_at: string | null
  item_count: number | null
  source: string | null
}

export async function readMeta(db: SupabaseClient, key: string): Promise<CacheMeta | null> {
  const { data } = await db.from('world_cache_meta').select('*').eq('key', key).maybeSingle()
  return data as CacheMeta | null
}

/** Atomically claims the refresh for [key]. Returns false if someone else holds it. */
export async function tryLock(db: SupabaseClient, key: string, holdSeconds: number): Promise<boolean> {
  const { data, error } = await db.rpc('claim_world_cache_refresh', {
    cache_key: key,
    hold_seconds: holdSeconds,
  })
  if (error) {
    console.error('claim_world_cache_refresh failed:', error)
    return false
  }
  return data === true
}

export async function publish(
  db: SupabaseClient,
  key: string,
  object: string,
  payload: unknown,
  itemCount: number,
  source: string,
  cacheSeconds: number,
) {
  const body = new Blob([JSON.stringify(payload)], { type: 'application/json' })
  const { error } = await db.storage.from(BUCKET).upload(object, body, {
    upsert: true,
    contentType: 'application/json',
    cacheControl: String(cacheSeconds),
  })
  if (error) throw error

  await db.from('world_cache_meta').upsert({
    key,
    fetched_at: new Date().toISOString(),
    item_count: itemCount,
    source,
    refreshing_until: null,
  })
}

export async function releaseLock(db: SupabaseClient, key: string) {
  await db.from('world_cache_meta').update({ refreshing_until: null }).eq('key', key)
}

export function ageMs(meta: CacheMeta | null): number {
  if (!meta?.fetched_at) return Number.POSITIVE_INFINITY
  return Date.now() - new Date(meta.fetched_at).getTime()
}
