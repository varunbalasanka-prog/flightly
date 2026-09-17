import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// One place for every outbound data request the world view makes.
///
/// Two paths:
/// * [proxy] — the `geo-proxy` Edge Function, for sources that send no CORS
///   headers, are rate-limited per IP, or aren't JSON (METAR, flight traces,
///   military traffic, OpenStreetMap installations, news RSS). Parameters are
///   validated server-side and responses are cached there.
/// * [getJson] — direct requests to sources that are CORS-enabled and polite
///   to call from a device (Radio Browser, Open-Meteo, OSRM, CelesTrak, USGS,
///   adsbdb, public Storage snapshots).
///
/// Every call returns null on failure instead of throwing, so a single flaky
/// layer never takes a whole screen down.
class DataGateway {
  DataGateway._();
  static final DataGateway instance = DataGateway._();

  static final http.Client _client = http.Client();
  static const _userAgent = 'SkyPulse/0.1 (+https://github.com/varunbalasanka-prog/flightly)';

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<dynamic> proxy(
    String source, [
    Map<String, dynamic> params = const {},
    Duration timeout = const Duration(seconds: 40),
  ]) async {
    try {
      final response = await _supabase.functions
          .invoke('geo-proxy', body: {'source': source, 'params': params})
          .timeout(timeout);
      if (response.status != 200) return null;
      final data = response.data;
      final decoded = data is String ? jsonDecode(data) : data;
      if (decoded is Map && decoded['notFound'] == true) return null;
      return decoded;
    } catch (e) {
      debugPrint('geo-proxy $source failed: $e');
      return null;
    }
  }

  /// Invokes any Edge Function and returns its decoded JSON body.
  Future<dynamic> function(
    String name, {
    Map<String, dynamic> body = const {},
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final response = await _supabase.functions.invoke(name, body: body).timeout(timeout);
      final data = response.data;
      return data is String ? jsonDecode(data) : data;
    } catch (e) {
      debugPrint('function $name failed: $e');
      return null;
    }
  }

  Future<dynamic> getJson(
    String url, {
    Duration timeout = const Duration(seconds: 25),
    Map<String, String> headers = const {},
  }) async {
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            headers: {
              // Browsers forbid setting User-Agent; native builds identify
              // themselves, which several of these services ask for.
              if (!kIsWeb) 'User-Agent': _userAgent,
              ...headers,
            },
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      debugPrint('GET $url failed: $e');
      return null;
    }
  }
}

/// A value plus when it was fetched, for simple time-based caches.
class Cached<T> {
  final T value;
  final DateTime at;
  Cached(this.value) : at = DateTime.now();
  bool fresherThan(Duration ttl) => DateTime.now().difference(at) < ttl;
}
