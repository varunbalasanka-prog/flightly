import { corsHeaders } from './cors.ts'

export const USER_AGENT = 'SkyPulse/0.1 (+https://github.com/varunbalasanka-prog/flightly)'

/** JSON response with CORS headers. */
export function json(body: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(typeof body === 'string' ? body : JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json', ...extra },
  })
}

/**
 * Fetch with a timeout and a hard response-size cap, so one oversized or hung
 * upstream cannot exhaust the function's memory or wall-clock budget.
 */
export async function fetchCapped(
  url: string,
  { timeoutMs = 10_000, maxBytes = 8 * 1024 * 1024, headers = {} as Record<string, string> } = {},
): Promise<{ status: number; body: string }> {
  const res = await fetch(url, {
    headers: { 'User-Agent': USER_AGENT, 'Accept-Encoding': 'gzip', ...headers },
    signal: AbortSignal.timeout(timeoutMs),
  })
  const reader = res.body?.getReader()
  if (!reader) return { status: res.status, body: '' }

  const chunks: Uint8Array[] = []
  let total = 0
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    total += value.byteLength
    if (total > maxBytes) {
      await reader.cancel()
      throw new Error(`Upstream response exceeded ${maxBytes} bytes`)
    }
    chunks.push(value)
  }
  const merged = new Uint8Array(total)
  let offset = 0
  for (const c of chunks) {
    merged.set(c, offset)
    offset += c.byteLength
  }
  return { status: res.status, body: new TextDecoder().decode(merged) }
}
