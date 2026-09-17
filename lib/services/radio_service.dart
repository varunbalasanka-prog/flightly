import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'data_gateway.dart';

/// A geolocated internet radio station from Radio Browser, a community-run
/// open directory (https://www.radio-browser.info).
///
/// Worth being clear about: these are internet streams tagged with a place,
/// often but not always a local FM broadcaster. Coverage is community-curated.
class RadioStation {
  final String uuid;
  final String name;
  final String streamUrl;
  final String homepage;
  final String favicon;
  final String countryCode;
  final String state;
  final List<String> tags;
  final String language;
  final String codec;
  final int bitrate;
  final double? lat;
  final double? lon;
  final int votes;

  const RadioStation({
    required this.uuid,
    required this.name,
    required this.streamUrl,
    required this.homepage,
    required this.favicon,
    required this.countryCode,
    required this.state,
    required this.tags,
    required this.language,
    required this.codec,
    required this.bitrate,
    required this.lat,
    required this.lon,
    required this.votes,
  });

  bool get looksLikeNews => tags.any((t) => const ['news', 'talk', 'information', 'public radio'].contains(t));

  static RadioStation? fromJson(Map<String, dynamic> j) {
    final url = (j['url_resolved'] as String?)?.trim() ?? '';
    final uuid = j['stationuuid'] as String?;
    if (uuid == null || url.isEmpty) return null;
    return RadioStation(
      uuid: uuid,
      name: (j['name'] as String? ?? 'Radio').trim(),
      streamUrl: url,
      homepage: j['homepage'] as String? ?? '',
      favicon: j['favicon'] as String? ?? '',
      countryCode: j['countrycode'] as String? ?? '',
      state: j['state'] as String? ?? '',
      tags: (j['tags'] as String? ?? '')
          .split(',')
          .map((t) => t.trim().toLowerCase())
          .where((t) => t.isNotEmpty)
          .toList(),
      language: j['language'] as String? ?? '',
      codec: j['codec'] as String? ?? '',
      bitrate: (j['bitrate'] as num?)?.toInt() ?? 0,
      lat: (j['geo_lat'] as num?)?.toDouble(),
      lon: (j['geo_long'] as num?)?.toDouble(),
      votes: (j['votes'] as num?)?.toInt() ?? 0,
    );
  }

  /// Compact form stored on a flight as its chosen destination station.
  Map<String, dynamic> toJson() => {
        'stationuuid': uuid,
        'name': name,
        'url_resolved': streamUrl,
        'homepage': homepage,
        'favicon': favicon,
        'countrycode': countryCode,
        'state': state,
        'tags': tags.join(','),
        'language': language,
        'codec': codec,
        'bitrate': bitrate,
        'geo_lat': lat,
        'geo_long': lon,
        'votes': votes,
      };
}

class RadioService {
  RadioService._();
  static final RadioService instance = RadioService._();

  // Radio Browser asks clients to spread load across its mirrors.
  static const _mirrors = [
    'https://de1.api.radio-browser.info',
    'https://de2.api.radio-browser.info',
    'https://fi1.api.radio-browser.info',
    'https://at1.api.radio-browser.info',
  ];
  int _mirror = 0;

  final _near = <String, Cached<List<RadioStation>>>{};
  Cached<List<RadioStation>>? _global;

  Future<dynamic> _get(String pathAndQuery) async {
    for (var attempt = 0; attempt < _mirrors.length; attempt++) {
      final base = _mirrors[(_mirror + attempt) % _mirrors.length];
      final data = await DataGateway.instance.getJson('$base$pathAndQuery');
      if (data != null) {
        _mirror = (_mirror + attempt) % _mirrors.length;
        return data;
      }
    }
    return null;
  }

  /// Streams a browser can actually play: HTTPS (an HTTPS page cannot load
  /// plain-HTTP audio) and not HLS playlists, which Chrome's audio element
  /// does not support. Native builds are also kept to HTTPS rather than
  /// enabling cleartext traffic app-wide.
  static bool playable(RadioStation s) {
    if (!s.streamUrl.startsWith('https://')) return false;
    if (kIsWeb && (s.streamUrl.contains('.m3u8') || s.codec.toUpperCase().contains('HLS'))) return false;
    return true;
  }

  /// Stations within [radiusKm] of a point, most popular first.
  Future<List<RadioStation>> near(double lat, double lon, {double radiusKm = 75, int limit = 60}) async {
    final key = '${lat.toStringAsFixed(1)},${lon.toStringAsFixed(1)},$radiusKm';
    final hit = _near[key];
    if (hit != null && hit.fresherThan(const Duration(hours: 6))) return hit.value;

    final data = await _get(
      '/json/stations/search?geo_lat=${lat.toStringAsFixed(4)}&geo_long=${lon.toStringAsFixed(4)}'
      '&geo_distance=${(radiusKm * 1000).round()}&has_geo_info=true&hidebroken=true&is_https=true'
      '&order=clickcount&reverse=true&limit=$limit',
    );
    final stations = _parse(data);
    _near[key] = Cached(stations);
    return stations;
  }

  /// The most-listened geolocated stations worldwide, for the globe layer.
  Future<List<RadioStation>> global({int limit = 750}) async {
    if (_global != null && _global!.fresherThan(const Duration(hours: 12))) return _global!.value;
    final data = await _get(
      '/json/stations/search?has_geo_info=true&hidebroken=true&is_https=true'
      '&order=clickcount&reverse=true&limit=$limit',
    );
    final stations = _parse(data);
    _global = Cached(stations);
    return stations;
  }

  List<RadioStation> _parse(dynamic data) => data is List
      ? data
          .whereType<Map<String, dynamic>>()
          .map(RadioStation.fromJson)
          .whereType<RadioStation>()
          .where(playable)
          .toList()
      : const [];

  /// Radio Browser uses this endpoint to count listens; they ask clients to
  /// call it when a station starts playing.
  void reportClick(RadioStation station) {
    _get('/json/url/${station.uuid}');
  }
}

enum RadioPlaybackState { idle, loading, playing, error }

/// The app-wide radio player, so a station keeps playing across screens.
class RadioPlayer {
  RadioPlayer._();
  static final RadioPlayer instance = RadioPlayer._();

  final AudioPlayer _player = AudioPlayer();
  final current = ValueNotifier<RadioStation?>(null);
  final state = ValueNotifier<RadioPlaybackState>(RadioPlaybackState.idle);
  final error = ValueNotifier<String?>(null);

  Future<void> play(RadioStation station) async {
    current.value = station;
    error.value = null;
    state.value = RadioPlaybackState.loading;
    try {
      await _player.stop();
      await _player.setUrl(station.streamUrl);
      RadioService.instance.reportClick(station);
      state.value = RadioPlaybackState.playing;
      // play() completes when playback stops, so don't await it.
      _player.play().catchError((Object e) {
        _fail('This station stopped responding.');
      });
    } catch (e) {
      _fail("Couldn't play ${station.name}. The stream may be offline.");
    }
  }

  void _fail(String message) {
    error.value = message;
    state.value = RadioPlaybackState.error;
  }

  Future<void> toggle() async {
    if (_player.playing) {
      await _player.pause();
      state.value = RadioPlaybackState.idle;
    } else if (current.value != null) {
      state.value = RadioPlaybackState.playing;
      _player.play();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    current.value = null;
    state.value = RadioPlaybackState.idle;
  }

  bool get isPlaying => _player.playing;
}
