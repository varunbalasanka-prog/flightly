import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../services/data_gateway.dart';
import '../../services/world_traffic_service.dart';
import 'cockpit_surface.dart';

/// Rides along with a live aircraft in 3D.
///
/// Positions come from adsb.lol every few seconds; the Cesium page smooths
/// between them. Everything shown is the aircraft's broadcast data.
class CockpitScreen extends StatefulWidget {
  final String? hex;
  final String? callsign;

  const CockpitScreen({super.key, this.hex, this.callsign});

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen> {
  CockpitSend? _send;
  Timer? _timer;
  int _misses = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onReady(CockpitSend send) {
    _send = send;
    send({'type': 'config', 'ionToken': AppConfig.cesiumIonToken});
    _poll();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  Future<void> _poll() async {
    final aircraft = await _fetch();
    if (!mounted || _send == null) return;
    if (aircraft == null) {
      if (++_misses >= 2) _send!({'type': 'lost'});
      return;
    }
    _misses = 0;
    _send!({
      'type': 'fix',
      'callsign': aircraft.label,
      'lat': aircraft.lat,
      'lon': aircraft.lon,
      'altFt': aircraft.altitudeFt,
      'speedKt': aircraft.groundSpeedKt,
      'trackDeg': aircraft.trackDeg,
      'onGround': aircraft.onGround,
    });
  }

  Future<TrafficAircraft?> _fetch() async {
    final hex = widget.hex?.trim().toLowerCase();
    if (hex != null && RegExp(r'^[0-9a-f]{6}$').hasMatch(hex)) {
      final data = await DataGateway.instance.proxy('adsb-hex', {'hex': hex});
      final list = data is Map ? data['ac'] as List? : null;
      if (list != null && list.isNotEmpty) {
        return TrafficAircraft.fromAdsb(list.first as Map<String, dynamic>, TrafficSource.adsbRegional);
      }
    }
    final callsign = widget.callsign?.trim().toUpperCase() ?? '';
    if (callsign.isNotEmpty) {
      final data = await DataGateway.instance.proxy('adsb-callsign', {'callsign': callsign});
      final list = data is Map ? data['ac'] as List? : null;
      if (list != null && list.isNotEmpty) {
        return TrafficAircraft.fromAdsb(list.first as Map<String, dynamic>, TrafficSource.adsbRegional);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        title: Text('Cockpit · ${widget.callsign?.isNotEmpty == true ? widget.callsign : widget.hex?.toUpperCase() ?? ''}'),
      ),
      body: CockpitSurface(onReady: _onReady),
    );
  }
}
