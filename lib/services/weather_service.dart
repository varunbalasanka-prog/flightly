import 'data_gateway.dart';

/// A real airport observation (METAR) from aviationweather.gov.
class Metar {
  final String icao;
  final String stationName;
  final String raw;
  final DateTime? observed;
  final double? tempC;
  final double? dewpointC;
  final int? windDirDeg;
  final int? windKt;
  final int? gustKt;

  /// Statute miles; "10+" style values become 10.
  final double? visibilitySm;

  /// Lowest broken/overcast layer in feet, i.e. the ceiling.
  final int? ceilingFt;

  /// VFR, MVFR, IFR or LIFR as reported.
  final String? flightCategory;

  const Metar({
    required this.icao,
    required this.stationName,
    required this.raw,
    this.observed,
    this.tempC,
    this.dewpointC,
    this.windDirDeg,
    this.windKt,
    this.gustKt,
    this.visibilitySm,
    this.ceilingFt,
    this.flightCategory,
  });

  static Metar? fromJson(Map<String, dynamic> j) {
    final icao = j['icaoId'] as String?;
    if (icao == null) return null;

    int? ceiling;
    for (final layer in (j['clouds'] as List? ?? const [])) {
      final cover = (layer as Map)['cover'];
      final base = (layer['base'] as num?)?.toInt();
      if ((cover == 'BKN' || cover == 'OVC' || cover == 'VV') && base != null) {
        ceiling = ceiling == null ? base : (base < ceiling ? base : ceiling);
      }
    }

    final visRaw = j['visib'];
    final vis = visRaw is num
        ? visRaw.toDouble()
        : double.tryParse('$visRaw'.replaceAll('+', ''));

    final gust = RegExp(r'G(\d{2,3})KT').firstMatch('${j['rawOb']}');
    final wdir = j['wdir'];

    return Metar(
      icao: icao,
      stationName: (j['name'] as String? ?? icao).split(',').first,
      raw: j['rawOb'] as String? ?? '',
      observed: j['obsTime'] is num
          ? DateTime.fromMillisecondsSinceEpoch((j['obsTime'] as num).toInt() * 1000, isUtc: true)
          : null,
      tempC: (j['temp'] as num?)?.toDouble(),
      dewpointC: (j['dewp'] as num?)?.toDouble(),
      // "VRB" (variable) arrives as a string.
      windDirDeg: wdir is num ? wdir.toInt() : null,
      windKt: (j['wspd'] as num?)?.toInt(),
      gustKt: gust == null ? null : int.tryParse(gust.group(1)!),
      visibilitySm: vis,
      ceilingFt: ceiling,
      flightCategory: j['fltCat'] as String?,
    );
  }

  /// Conditions that genuinely slow airport operations, in plain words.
  List<String> get operationalConcerns {
    final concerns = <String>[];
    if (flightCategory == 'LIFR') {
      concerns.add('Very low cloud or visibility at $icao (LIFR)');
    } else if (flightCategory == 'IFR') {
      concerns.add('Low cloud or visibility at $icao (IFR)');
    }
    final wind = gustKt ?? windKt;
    if (wind != null && wind >= 35) {
      concerns.add('Strong winds at $icao (${wind}kt)');
    } else if (wind != null && wind >= 25) {
      concerns.add('Gusty winds at $icao (${wind}kt)');
    }
    if (RegExp(r'\b(\+|VC)?TS').hasMatch(raw)) concerns.add('Thunderstorms reported at $icao');
    if (RegExp(r'\b(FZRA|FZDZ|SN|\+SN)\b').hasMatch(raw)) concerns.add('Snow or freezing precipitation at $icao');
    return concerns;
  }
}

/// Current conditions and the next hours from Open-Meteo (keyless).
class LocalWeather {
  final double temperatureC;
  final double apparentC;
  final int weatherCode;
  final double windKmh;
  final int cloudCoverPct;
  final double precipitationMm;
  final bool isDay;
  final List<HourlyForecast> nextHours;

  const LocalWeather({
    required this.temperatureC,
    required this.apparentC,
    required this.weatherCode,
    required this.windKmh,
    required this.cloudCoverPct,
    required this.precipitationMm,
    required this.isDay,
    required this.nextHours,
  });

  String get description => describeWeatherCode(weatherCode);
}

class HourlyForecast {
  final DateTime time;
  final double temperatureC;
  final int weatherCode;
  final int precipitationProbability;
  const HourlyForecast(this.time, this.temperatureC, this.weatherCode, this.precipitationProbability);
}

/// WMO weather interpretation codes, as documented by Open-Meteo.
String describeWeatherCode(int code) {
  if (code == 0) return 'Clear sky';
  if (code <= 2) return 'Partly cloudy';
  if (code == 3) return 'Overcast';
  if (code == 45 || code == 48) return 'Fog';
  if (code >= 51 && code <= 57) return 'Drizzle';
  if (code >= 61 && code <= 67) return 'Rain';
  if (code >= 71 && code <= 77) return 'Snow';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code == 85 || code == 86) return 'Snow showers';
  if (code >= 95) return 'Thunderstorm';
  return 'Unknown';
}

class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  final _metars = <String, Cached<Metar?>>{};
  final _local = <String, Cached<LocalWeather?>>{};

  Future<Metar?> metar(String icao) async => (await metars([icao]))[icao.toUpperCase()];

  Future<Map<String, Metar>> metars(List<String> icaoCodes) async {
    final wanted = icaoCodes
        .map((c) => c.toUpperCase())
        .where((c) => RegExp(r'^[A-Z0-9]{4}$').hasMatch(c))
        .toSet();
    final result = <String, Metar>{};
    final missing = <String>[];
    for (final c in wanted) {
      final hit = _metars[c];
      if (hit != null && hit.fresherThan(const Duration(minutes: 5))) {
        if (hit.value != null) result[c] = hit.value!;
      } else {
        missing.add(c);
      }
    }
    if (missing.isEmpty) return result;

    final data = await DataGateway.instance.proxy('metar', {'ids': missing.join(',')});
    final seen = <String>{};
    if (data is List) {
      // hours=2 returns several reports per station, newest first.
      for (final row in data.whereType<Map<String, dynamic>>()) {
        final m = Metar.fromJson(row);
        if (m == null || !seen.add(m.icao)) continue;
        result[m.icao] = m;
        _metars[m.icao] = Cached(m);
      }
    }
    for (final c in missing) {
      _metars.putIfAbsent(c, () => Cached(null));
    }
    return result;
  }

  Future<LocalWeather?> local(double lat, double lon) async {
    final key = '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
    final hit = _local[key];
    if (hit != null && hit.fresherThan(const Duration(minutes: 15))) return hit.value;

    final data = await DataGateway.instance.getJson(
      'https://api.open-meteo.com/v1/forecast?latitude=${lat.toStringAsFixed(4)}'
      '&longitude=${lon.toStringAsFixed(4)}'
      '&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,cloud_cover,precipitation,is_day'
      '&hourly=temperature_2m,weather_code,precipitation_probability&forecast_hours=12&timezone=auto',
    );
    LocalWeather? weather;
    if (data is Map<String, dynamic> && data['current'] is Map) {
      final c = data['current'] as Map;
      final h = data['hourly'] as Map? ?? const {};
      final times = (h['time'] as List? ?? const []).cast<String>();
      final hours = <HourlyForecast>[];
      for (var i = 0; i < times.length; i++) {
        hours.add(HourlyForecast(
          DateTime.parse(times[i]),
          ((h['temperature_2m'] as List)[i] as num).toDouble(),
          ((h['weather_code'] as List)[i] as num).toInt(),
          (((h['precipitation_probability'] as List?)?[i] as num?) ?? 0).toInt(),
        ));
      }
      weather = LocalWeather(
        temperatureC: (c['temperature_2m'] as num).toDouble(),
        apparentC: (c['apparent_temperature'] as num? ?? c['temperature_2m'] as num).toDouble(),
        weatherCode: (c['weather_code'] as num).toInt(),
        windKmh: (c['wind_speed_10m'] as num? ?? 0).toDouble(),
        cloudCoverPct: (c['cloud_cover'] as num? ?? 0).toInt(),
        precipitationMm: (c['precipitation'] as num? ?? 0).toDouble(),
        isDay: (c['is_day'] as num? ?? 1) == 1,
        nextHours: hours,
      );
    }
    _local[key] = Cached(weather);
    return weather;
  }
}
