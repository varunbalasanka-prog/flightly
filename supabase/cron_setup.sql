-- =============================================
-- SkyPulse — pg_cron Setup for Flight Polling
-- Run this in the Supabase SQL Editor
-- =============================================

-- Enable pg_cron (if not already enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Note: Replace 'YOUR_PROJECT_REF' and 'YOUR_CRON_SECRET_KEY' with actual values.
-- The CRON_SECRET_KEY must be stored in the Edge Function's environment variables.

SELECT cron.schedule(
  'poll-flights-every-15-mins', -- name of the cron job
  '*/15 * * * *', -- every 15 minutes
  $$
    SELECT net.http_post(
      url:='https://YOUR_PROJECT_REF.supabase.co/functions/v1/poll-flights',
      headers:='{"Content-Type": "application/json", "Authorization": "Bearer YOUR_CRON_SECRET_KEY"}'::jsonb
    ) as request_id;
  $$
);

-- To unschedule if needed:
-- SELECT cron.unschedule('poll-flights-every-15-mins');
