import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central configuration for SkyPulse.
/// All external service credentials are loaded from .env
/// and never hardcoded in the app.
class AppConfig {
  AppConfig._();

  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? 'https://your-project.supabase.co';

  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  static String get googleWebClientId =>
      dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';

  /// Optional. CARTO now requires a key for its raster basemaps; without one
  /// every tile is watermarked. Leave unset to use keyless OpenStreetMap tiles.
  static String get cartoApiKey => dotenv.env['CARTO_API_KEY'] ?? '';

  /// Aviationstack credentials are NEVER stored in the app.
  /// They live exclusively in Supabase Vault secrets.
  /// The app only calls authenticated Edge Functions.

  // Quota constants
  static const int globalMonthlyRequestLimit = 100;
  static const int userMonthlyFlightLimit = 2;
  static const int userActiveMonitoredLimit = 1;
  static const int pollingIntervalMinutes = 15;
  static const int pollingStartBeforeDepartureHours = 2;
  static const int staleDataThresholdMinutes = 30;

  /// Length of a share invite code. Must match the generator in the
  /// share-flight Edge Function.
  static const int inviteCodeLength = 8;

  // Beta
  static const int maxBetaUsers = 5;
  static const String appVersion = '0.1.0-beta';
  static const String appName = 'SkyPulse';
}
