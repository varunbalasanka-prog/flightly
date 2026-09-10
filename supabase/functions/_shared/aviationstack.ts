import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const AVIATIONSTACK_API_URL = 'http://api.aviationstack.com/v1/flights';

// Get Aviationstack API key from Supabase Vault or environment
// In a real app, this should be stored securely in Supabase Vault.
// For this demo/beta, we'll assume it's in Deno.env
export async function getAviationstackKey(): Promise<string> {
  const key = Deno.env.get('AVIATIONSTACK_API_KEY');
  if (!key) {
    throw new Error('Aviationstack API key not found in environment');
  }
  return key;
}

export async function checkGlobalQuota(supabase: any): Promise<boolean> {
  const { data, error } = await supabase.rpc('check_quota');
  if (error) {
    console.error('Error checking quota:', error);
    return false; // Fail closed to protect quota
  }
  return data === true;
}

export async function incrementGlobalQuota(supabase: any): Promise<void> {
  const { error } = await supabase.rpc('increment_global_quota');
  if (error) {
    console.error('Error incrementing quota:', error);
  }
}

export async function fetchFlightFromAviationstack(flightIata: string): Promise<any> {
  const apiKey = await getAviationstackKey();
  const url = `${AVIATIONSTACK_API_URL}?access_key=${apiKey}&flight_iata=${encodeURIComponent(flightIata)}`;
  
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Aviationstack API error: ${response.status} ${response.statusText}`);
  }
  
  const data = await response.json();
  return data;
}

export function normalizeAviationstackData(apiFlight: any): any {
  // Map Aviationstack's response schema to our DB schema
  return {
    flight_number: apiFlight.flight?.iata,
    airline_iata: apiFlight.airline?.iata,
    airline_name: apiFlight.airline?.name,
    dep_airport_iata: apiFlight.departure?.iata,
    dep_airport_name: apiFlight.departure?.airport,
    arr_airport_iata: apiFlight.arrival?.iata,
    arr_airport_name: apiFlight.arrival?.airport,
    scheduled_departure: apiFlight.departure?.scheduled,
    scheduled_arrival: apiFlight.arrival?.scheduled,
    estimated_departure: apiFlight.departure?.estimated,
    estimated_arrival: apiFlight.arrival?.estimated,
    actual_departure: apiFlight.departure?.actual,
    actual_arrival: apiFlight.arrival?.actual,
    dep_terminal: apiFlight.departure?.terminal,
    dep_gate: apiFlight.departure?.gate,
    arr_terminal: apiFlight.arrival?.terminal,
    arr_gate: apiFlight.arrival?.gate,
    baggage_claim: apiFlight.arrival?.baggage,
    dep_delay_minutes: apiFlight.departure?.delay,
    arr_delay_minutes: apiFlight.arrival?.delay,
    status: apiFlight.flight_status,
    aircraft: apiFlight.aircraft ? {
      registration: apiFlight.aircraft.registration,
      icaoCode: apiFlight.aircraft.icao,
      modelName: apiFlight.aircraft.icao24,
    } : null,
  };
}
