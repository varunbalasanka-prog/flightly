-- =============================================
-- SkyPulse — Complete Supabase Database Schema
-- Run this once in the Supabase Dashboard > SQL Editor
-- =============================================

-- ── 0. Enable Required Extensions ──
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================
-- 1. PROFILES
-- =============================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  display_name TEXT,
  avatar_url TEXT,
  fcm_token TEXT,
  timezone TEXT DEFAULT 'UTC',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', NEW.email),
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Backfill profile for any existing user who might already have signed up
INSERT INTO public.profiles (id, email, display_name)
SELECT id, email, COALESCE(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', email)
FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- =============================================
-- 2. AIRPORTS (Pre-seeded global hub registry)
-- =============================================
CREATE TABLE IF NOT EXISTS public.airports (
  iata_code TEXT PRIMARY KEY,
  icao_code TEXT,
  name TEXT NOT NULL,
  city TEXT NOT NULL,
  country TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  timezone TEXT DEFAULT 'UTC',
  delay_index INT DEFAULT 0,
  weather_condition TEXT DEFAULT 'Clear'
);

INSERT INTO public.airports (iata_code, icao_code, name, city, country, latitude, longitude, timezone, delay_index, weather_condition)
VALUES
  ('JFK', 'KJFK', 'John F. Kennedy International Airport', 'New York', 'United States', 40.6413, -73.7781, 'America/New_York', 15, 'Clear'),
  ('LHR', 'EGLL', 'Heathrow Airport', 'London', 'United Kingdom', 51.4700, -0.4543, 'Europe/London', 20, 'Light Rain'),
  ('DXB', 'OMDB', 'Dubai International Airport', 'Dubai', 'United Arab Emirates', 25.2532, 55.3657, 'Asia/Dubai', 5, 'Sunny'),
  ('LAX', 'KLAX', 'Los Angeles International Airport', 'Los Angeles', 'United States', 33.9416, -118.4085, 'America/Los_Angeles', 10, 'Clear'),
  ('ORD', 'KORD', 'O''Hare International Airport', 'Chicago', 'United States', 41.9742, -87.9073, 'America/Chicago', 25, 'Windy'),
  ('DFW', 'KDFW', 'Dallas/Fort Worth International Airport', 'Dallas', 'United States', 32.8998, -97.0403, 'America/Chicago', 10, 'Clear'),
  ('ATL', 'KATL', 'Hartsfield-Jackson Atlanta International Airport', 'Atlanta', 'United States', 33.6407, -84.4277, 'America/New_York', 15, 'Partly Cloudy'),
  ('SFO', 'KSFO', 'San Francisco International Airport', 'San Francisco', 'United States', 37.6213, -122.3790, 'America/Los_Angeles', 30, 'Fog'),
  ('CDG', 'LFPG', 'Charles de Gaulle Airport', 'Paris', 'France', 49.0097, 2.5479, 'Europe/Paris', 15, 'Cloudy'),
  ('FRA', 'EDDF', 'Frankfurt Airport', 'Frankfurt', 'Germany', 50.0379, 8.5622, 'Europe/Berlin', 10, 'Clear'),
  ('AMS', 'EHAM', 'Amsterdam Airport Schiphol', 'Amsterdam', 'Netherlands', 52.3105, 4.7683, 'Europe/Amsterdam', 20, 'Light Rain'),
  ('SIN', 'WSSS', 'Singapore Changi Airport', 'Singapore', 'Singapore', 1.3644, 103.9915, 'Asia/Singapore', 5, 'Humid'),
  ('HND', 'RJTT', 'Tokyo Haneda Airport', 'Tokyo', 'Japan', 35.5494, 139.7798, 'Asia/Tokyo', 5, 'Clear'),
  ('SYD', 'YSSY', 'Sydney Kingsford Smith Airport', 'Sydney', 'Australia', -33.9399, 151.1753, 'Australia/Sydney', 10, 'Sunny'),
  ('DEL', 'VIDP', 'Indira Gandhi International Airport', 'New Delhi', 'India', 28.5562, 77.1000, 'Asia/Kolkata', 15, 'Haze'),
  ('BOM', 'VABB', 'Chhatrapati Shivaji Maharaj International Airport', 'Mumbai', 'India', 19.0896, 72.8656, 'Asia/Kolkata', 20, 'Partly Cloudy'),
  ('BLR', 'VOBL', 'Kempegowda International Airport', 'Bengaluru', 'India', 13.1986, 77.7066, 'Asia/Kolkata', 10, 'Pleasant'),
  ('MAA', 'VOMM', 'Chennai International Airport', 'Chennai', 'India', 12.9941, 80.1709, 'Asia/Kolkata', 10, 'Clear'),
  ('HYD', 'VOHS', 'Rajiv Gandhi International Airport', 'Hyderabad', 'India', 17.2403, 78.4294, 'Asia/Kolkata', 5, 'Clear')
ON CONFLICT (iata_code) DO UPDATE SET
  name = EXCLUDED.name,
  city = EXCLUDED.city,
  country = EXCLUDED.country,
  latitude = EXCLUDED.latitude,
  longitude = EXCLUDED.longitude;

-- =============================================
-- 3. TRIPS
-- =============================================
CREATE TABLE IF NOT EXISTS public.trips (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trips_user_id ON public.trips(user_id);

-- =============================================
-- 4. FLIGHTS
-- =============================================
CREATE TABLE IF NOT EXISTS public.flights (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  trip_id UUID REFERENCES public.trips(id) ON DELETE SET NULL,
  flight_number TEXT NOT NULL,
  airline_iata TEXT,
  airline_name TEXT,
  dep_airport_iata TEXT NOT NULL,
  dep_airport_name TEXT,
  arr_airport_iata TEXT NOT NULL,
  arr_airport_name TEXT,
  scheduled_departure TIMESTAMPTZ NOT NULL,
  scheduled_arrival TIMESTAMPTZ NOT NULL,
  estimated_departure TIMESTAMPTZ,
  estimated_arrival TIMESTAMPTZ,
  actual_departure TIMESTAMPTZ,
  actual_arrival TIMESTAMPTZ,
  dep_terminal TEXT,
  dep_gate TEXT,
  arr_terminal TEXT,
  arr_gate TEXT,
  baggage_claim TEXT,
  dep_delay_minutes INT DEFAULT 0,
  arr_delay_minutes INT DEFAULT 0,
  status TEXT DEFAULT 'scheduled',
  aircraft JSONB,
  is_manual_entry BOOLEAN DEFAULT FALSE,
  is_history BOOLEAN DEFAULT FALSE,
  data_source TEXT DEFAULT 'openskynetwork',
  last_updated TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_flights_user_id ON public.flights(user_id);
CREATE INDEX IF NOT EXISTS idx_flights_trip_id ON public.flights(trip_id);
CREATE INDEX IF NOT EXISTS idx_flights_flight_number ON public.flights(flight_number);
CREATE INDEX IF NOT EXISTS idx_flights_status ON public.flights(status);
CREATE INDEX IF NOT EXISTS idx_flights_scheduled_dep ON public.flights(scheduled_departure);

-- =============================================
-- 5. MONITORED FLIGHTS (active polling targets)
-- =============================================
CREATE TABLE IF NOT EXISTS public.monitored_flights (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  flight_id UUID NOT NULL REFERENCES public.flights(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_active BOOLEAN DEFAULT TRUE,
  last_polled_at TIMESTAMPTZ,
  poll_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(flight_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_monitored_active ON public.monitored_flights(is_active)
  WHERE is_active = TRUE;

-- =============================================
-- 6. STATUS SNAPSHOTS (historical status records)
-- =============================================
CREATE TABLE IF NOT EXISTS public.status_snapshots (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  flight_id UUID NOT NULL REFERENCES public.flights(id) ON DELETE CASCADE,
  status TEXT,
  dep_delay_minutes INT,
  arr_delay_minutes INT,
  dep_gate TEXT,
  arr_gate TEXT,
  dep_terminal TEXT,
  arr_terminal TEXT,
  baggage_claim TEXT,
  estimated_departure TIMESTAMPTZ,
  estimated_arrival TIMESTAMPTZ,
  actual_departure TIMESTAMPTZ,
  actual_arrival TIMESTAMPTZ,
  aircraft_icao TEXT,
  aircraft_registration TEXT,
  delay_risk JSONB,
  data_source TEXT DEFAULT 'openskynetwork',
  fetched_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_snapshots_flight_id ON public.status_snapshots(flight_id);
CREATE INDEX IF NOT EXISTS idx_snapshots_fetched_at ON public.status_snapshots(fetched_at DESC);

-- =============================================
-- 7. NOTIFICATION EVENTS
-- =============================================
CREATE TABLE IF NOT EXISTS public.notification_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  flight_id UUID NOT NULL REFERENCES public.flights(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  metadata JSONB,
  is_sent BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notification_events(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_flight_id ON public.notification_events(flight_id);

-- =============================================
-- 8. FLIGHT SHARES
-- =============================================
CREATE TABLE IF NOT EXISTS public.flight_shares (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  flight_id UUID NOT NULL REFERENCES public.flights(id) ON DELETE CASCADE,
  owner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  shared_with_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  invite_email TEXT,
  invite_code TEXT UNIQUE,
  status TEXT DEFAULT 'pending',
  is_read_only BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shares_owner ON public.flight_shares(owner_id);
CREATE INDEX IF NOT EXISTS idx_shares_shared_with ON public.flight_shares(shared_with_id);
CREATE INDEX IF NOT EXISTS idx_shares_invite_code ON public.flight_shares(invite_code);

-- =============================================
-- 9. USAGE QUOTAS
-- =============================================
CREATE TABLE IF NOT EXISTS public.usage_quotas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  period_start TIMESTAMPTZ NOT NULL,
  period_end TIMESTAMPTZ NOT NULL,
  global_requests_used INT DEFAULT 0,
  global_requests_limit INT DEFAULT 1000,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(period_start)
);

CREATE TABLE IF NOT EXISTS public.user_quotas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  period_start TIMESTAMPTZ NOT NULL,
  monthly_flights_used INT DEFAULT 0,
  monthly_flights_limit INT DEFAULT 50,
  active_monitored_count INT DEFAULT 0,
  active_monitored_limit INT DEFAULT 10,
  UNIQUE(user_id, period_start)
);

-- =============================================
-- 10. ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

ALTER TABLE public.airports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read airports" ON public.airports;
CREATE POLICY "Anyone can read airports" ON public.airports FOR SELECT USING (TRUE);

ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage own trips" ON public.trips;
CREATE POLICY "Users can manage own trips" ON public.trips FOR ALL USING (auth.uid() = user_id);

ALTER TABLE public.flights ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage own flights" ON public.flights;
CREATE POLICY "Users can manage own flights" ON public.flights FOR ALL USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can view shared flights" ON public.flights;
CREATE POLICY "Users can view shared flights" ON public.flights FOR SELECT USING (
  id IN (
    SELECT flight_id FROM public.flight_shares
    WHERE shared_with_id = auth.uid() AND status = 'accepted'
  )
);

ALTER TABLE public.monitored_flights ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage own monitors" ON public.monitored_flights;
CREATE POLICY "Users can manage own monitors" ON public.monitored_flights FOR ALL USING (auth.uid() = user_id);

ALTER TABLE public.status_snapshots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own flight snapshots" ON public.status_snapshots;
CREATE POLICY "Users can view own flight snapshots" ON public.status_snapshots FOR SELECT USING (
  flight_id IN (SELECT id FROM public.flights WHERE user_id = auth.uid())
  OR flight_id IN (
    SELECT flight_id FROM public.flight_shares
    WHERE shared_with_id = auth.uid() AND status = 'accepted'
  )
);
-- Snapshots are written by the poll-flights Edge Function using the service
-- role key, which bypasses RLS. Clients may only insert snapshots for flights
-- they own; the previous WITH CHECK (TRUE) let any signed-in user forge a
-- status (gate change, "cancelled", ...) on ANY user's flight.
DROP POLICY IF EXISTS "Users can insert snapshots" ON public.status_snapshots;
CREATE POLICY "Users can insert snapshots" ON public.status_snapshots FOR INSERT WITH CHECK (
  flight_id IN (SELECT id FROM public.flights WHERE user_id = auth.uid())
);

ALTER TABLE public.notification_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notification_events;
CREATE POLICY "Users can view own notifications" ON public.notification_events FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert notifications" ON public.notification_events;
CREATE POLICY "Users can insert notifications" ON public.notification_events FOR INSERT WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.flight_shares ENABLE ROW LEVEL SECURITY;
-- `FOR ALL USING (owner_id = auth.uid())` alone let a client insert a share
-- row naming itself as owner for a flight_id it does not own, then redeem it
-- from a second account. The WITH CHECK ties the share to real ownership.
DROP POLICY IF EXISTS "Owners can manage shares" ON public.flight_shares;
CREATE POLICY "Owners can manage shares" ON public.flight_shares FOR ALL
  USING (auth.uid() = owner_id)
  WITH CHECK (
    auth.uid() = owner_id
    AND flight_id IN (SELECT id FROM public.flights WHERE user_id = auth.uid())
  );
-- A recipient may only see shares addressed to them. Previously this policy
-- OR-ed in `auth.role() = 'authenticated'`, which let ANY signed-in user read
-- every row in this table -- including every invite_code and invite_email.
DROP POLICY IF EXISTS "Shared users can view shares" ON public.flight_shares;
CREATE POLICY "Shared users can view shares" ON public.flight_shares FOR SELECT USING (
  shared_with_id = auth.uid()
);

-- Claiming an invite is done exclusively through join_shared_flight(), which is
-- SECURITY DEFINER. There is deliberately no direct UPDATE policy for
-- recipients: the previous one allowed any authenticated user to UPDATE any
-- row, i.e. to point any share at themselves and read someone else's flights.

ALTER TABLE public.usage_quotas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can view quotas" ON public.usage_quotas;
CREATE POLICY "Authenticated users can view quotas" ON public.usage_quotas FOR SELECT USING (auth.role() = 'authenticated');

ALTER TABLE public.user_quotas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own quotas" ON public.user_quotas;
CREATE POLICY "Users can view own quotas" ON public.user_quotas FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can manage own quotas" ON public.user_quotas;
CREATE POLICY "Users can manage own quotas" ON public.user_quotas FOR ALL USING (auth.uid() = user_id);

-- =============================================
-- 11. HELPER STORED PROCEDURES
-- =============================================

-- Increment quota counter
CREATE OR REPLACE FUNCTION public.increment_global_quota()
RETURNS VOID AS $$
DECLARE
  current_period TIMESTAMPTZ;
BEGIN
  current_period := date_trunc('month', NOW());
  INSERT INTO public.usage_quotas (period_start, period_end, global_requests_used, global_requests_limit)
  VALUES (current_period, current_period + INTERVAL '1 month', 1, 1000)
  ON CONFLICT (period_start) DO UPDATE
  SET global_requests_used = public.usage_quotas.global_requests_used + 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Check quota
CREATE OR REPLACE FUNCTION public.check_quota()
RETURNS BOOLEAN AS $$
DECLARE
  current_used INT;
  current_limit INT;
BEGIN
  SELECT global_requests_used, global_requests_limit
  INTO current_used, current_limit
  FROM public.usage_quotas
  WHERE period_start = date_trunc('month', NOW());

  IF current_used IS NULL THEN
    RETURN TRUE;
  END IF;

  RETURN current_used < current_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Join shared flight via invite code
CREATE OR REPLACE FUNCTION public.join_shared_flight(code TEXT)
RETURNS JSONB AS $$
DECLARE
  share_record RECORD;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'You must be signed in');
  END IF;

  -- Only an unclaimed, non-revoked invite can be redeemed. Without the
  -- status/shared_with_id guards this would happily re-point an already
  -- accepted share at the caller, silently revoking the original recipient,
  -- and would still honour codes the owner had revoked.
  SELECT * INTO share_record
  FROM public.flight_shares
  WHERE invite_code = UPPER(TRIM(code))
    AND status = 'pending'
    AND shared_with_id IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired invite code');
  END IF;

  -- The owner redeeming their own code would grant themselves a duplicate row.
  IF share_record.owner_id = auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already own this flight');
  END IF;

  UPDATE public.flight_shares
  SET shared_with_id = auth.uid(),
      status = 'accepted'
  WHERE id = share_record.id;

  RETURN jsonb_build_object('success', true, 'flight_id', share_record.flight_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ── Function privileges ──
-- Postgres grants EXECUTE to PUBLIC by default and anon/authenticated inherit
-- from it, so every SECURITY DEFINER function here was reachable over
-- /rest/v1/rpc by anonymous callers. increment_global_quota in particular let
-- an unauthenticated caller burn the monthly provider quota at will.
REVOKE EXECUTE ON FUNCTION public.handle_new_user()        FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.increment_global_quota() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_quota()            FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.join_shared_flight(TEXT) FROM PUBLIC;

-- Quota helpers are called only by Edge Functions using the service role key.
GRANT EXECUTE ON FUNCTION public.increment_global_quota() TO service_role;
GRANT EXECUTE ON FUNCTION public.check_quota()            TO service_role;

-- Redeeming an invite is a signed-in user action.
GRANT EXECUTE ON FUNCTION public.join_shared_flight(TEXT) TO authenticated;

-- handle_new_user is a trigger function and is intentionally granted to nobody.

-- =============================================
-- 12. ENABLE REALTIME PUBLICATION
-- =============================================
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.flights;
  EXCEPTION WHEN duplicate_object THEN END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.trips;
  EXCEPTION WHEN duplicate_object THEN END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.status_snapshots;
  EXCEPTION WHEN duplicate_object THEN END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notification_events;
  EXCEPTION WHEN duplicate_object THEN END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.flight_shares;
  EXCEPTION WHEN duplicate_object THEN END;
END $$;

-- =============================================
-- 13. WORLD VIEW CACHE (shared global snapshots)
-- =============================================
-- Expensive worldwide datasets (every aircraft, every public camera, satellite
-- element sets) are refreshed by one caller at a time and served to everyone
-- from a public Storage bucket. Service role only: no client policies.
CREATE TABLE IF NOT EXISTS public.world_cache_meta (
  key TEXT PRIMARY KEY,
  fetched_at TIMESTAMPTZ,
  item_count INT,
  source TEXT,
  refreshing_until TIMESTAMPTZ
);
ALTER TABLE public.world_cache_meta ENABLE ROW LEVEL SECURITY;

-- Atomically claims a refresh so concurrent requests don't all hit upstream.
CREATE OR REPLACE FUNCTION public.claim_world_cache_refresh(cache_key TEXT, hold_seconds INT)
RETURNS BOOLEAN AS $$
DECLARE
  claimed BOOLEAN;
BEGIN
  INSERT INTO public.world_cache_meta (key) VALUES (cache_key) ON CONFLICT (key) DO NOTHING;
  UPDATE public.world_cache_meta
     SET refreshing_until = NOW() + make_interval(secs => hold_seconds)
   WHERE key = cache_key
     AND (refreshing_until IS NULL OR refreshing_until < NOW())
  RETURNING TRUE INTO claimed;
  RETURN COALESCE(claimed, FALSE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.claim_world_cache_refresh(TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_world_cache_refresh(TEXT, INT) TO service_role;

-- Public-read bucket for the snapshots. Everything in it is already public data
-- (ADS-B broadcasts, published camera catalogs, orbital elements). Only the
-- service role can write: there are no insert/update policies for clients.
INSERT INTO storage.buckets (id, name, public)
VALUES ('world-cache', 'world-cache', TRUE)
ON CONFLICT (id) DO NOTHING;

-- =============================================
-- 14. DESTINATION + TRACKING EXTRAS
-- =============================================
-- The radio station a traveller picked for their destination.
ALTER TABLE public.flights ADD COLUMN IF NOT EXISTS destination_radio JSONB;
-- Tail number of the aircraft operating (or flying in to operate) this flight,
-- entered by the traveller, for "where's my plane".
ALTER TABLE public.flights ADD COLUMN IF NOT EXISTS aircraft_registration TEXT;

-- Real flown path, captured while adsb.lol still holds it (~24h), so the
-- flight can be replayed later.
CREATE TABLE IF NOT EXISTS public.flight_tracks (
  flight_id UUID PRIMARY KEY REFERENCES public.flights(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  points JSONB NOT NULL,
  source TEXT DEFAULT 'adsb.lol',
  captured_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.flight_tracks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage own tracks" ON public.flight_tracks;
CREATE POLICY "Users can manage own tracks" ON public.flight_tracks FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND flight_id IN (SELECT id FROM public.flights WHERE user_id = auth.uid())
  );

-- Per-user daily spend for the flight assistant, enforced server-side.
CREATE TABLE IF NOT EXISTS public.assistant_usage (
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day DATE NOT NULL DEFAULT CURRENT_DATE,
  requests INT NOT NULL DEFAULT 0,
  input_tokens INT NOT NULL DEFAULT 0,
  output_tokens INT NOT NULL DEFAULT 0,
  cost_usd NUMERIC(10, 5) NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day)
);
ALTER TABLE public.assistant_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own assistant usage" ON public.assistant_usage;
CREATE POLICY "Users can view own assistant usage" ON public.assistant_usage FOR SELECT
  USING (auth.uid() = user_id);
