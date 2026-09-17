import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../blocs/flight/flight_bloc.dart';
import '../../config/app_config.dart';
import '../../models/models.dart';
import '../../services/airport_directory.dart';
import '../../services/place_intel_service.dart';
import '../../services/world_traffic_service.dart';

// ── Where's my plane ──────────────────────────────────────────────────────

/// Tracks the actual airframe operating a flight by its tail number.
///
/// Public ADS-B data has no link from a flight number to the aircraft that
/// will fly it, so the traveller supplies the registration (airline apps
/// usually show it). From then on we can see where that aircraft really is.
class WhereIsMyPlaneCard extends StatefulWidget {
  final Flight flight;
  final void Function(TrafficAircraft? aircraft, double? distanceKm)? onPosition;

  const WhereIsMyPlaneCard({super.key, required this.flight, this.onPosition});

  @override
  State<WhereIsMyPlaneCard> createState() => _WhereIsMyPlaneCardState();
}

class _WhereIsMyPlaneCardState extends State<WhereIsMyPlaneCard> {
  TrafficAircraft? _aircraft;
  double? _distanceKm;
  AirportInfoRecord? _near;
  bool _loading = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(covariant WhereIsMyPlaneCard old) {
    super.didUpdateWidget(old);
    if (old.flight.aircraftRegistration != widget.flight.aircraftRegistration) _lookup();
  }

  Future<void> _lookup() async {
    final reg = widget.flight.aircraftRegistration;
    if (reg == null || reg.isEmpty) return;
    setState(() => _loading = true);
    final aircraft = await WorldTrafficService.instance.byRegistration(reg);
    final departure = await AirportDirectory.instance.lookup(widget.flight.departureAirportIata);
    double? distance;
    AirportInfoRecord? near;
    if (aircraft != null) {
      if (departure != null) distance = haversineKm(aircraft.lat, aircraft.lon, departure.lat, departure.lon);
      final nearby = await AirportDirectory.instance.nearest(aircraft.lat, aircraft.lon, radiusKm: 40, limit: 1);
      near = nearby.isEmpty ? null : nearby.first;
    }
    if (!mounted) return;
    setState(() {
      _aircraft = aircraft;
      _distanceKm = distance;
      _near = near;
      _loading = false;
      _checked = true;
    });
    widget.onPosition?.call(aircraft, distance);
  }

  Future<void> _editRegistration() async {
    final controller = TextEditingController(text: widget.flight.aircraftRegistration ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Your aircraft's tail number"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Airline apps and boarding screens usually show it, e.g. G-XWBA or N628TS. '
              "We'll track that aircraft's live position.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'Registration'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (value == null || !mounted) return;
    final reg = value.trim().toUpperCase();
    if (reg.isNotEmpty && !RegExp(r'^[A-Z0-9-]{2,10}$').hasMatch(reg)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That doesn't look like a registration.")));
      return;
    }
    try {
      await context.read<FlightBloc>().updateFlight(widget.flight.copyWith(aircraftRegistration: reg));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save the registration.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reg = widget.flight.aircraftRegistration;
    final a = _aircraft;

    Widget body;
    if (reg == null || reg.isEmpty) {
      body = Text(
        "Add your aircraft's tail number to see where it is before you board.",
        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      );
    } else if (_loading && !_checked) {
      body = const LinearProgressIndicator(minHeight: 2);
    } else if (a == null) {
      body = Text(
        '$reg is not transmitting right now — it is likely parked with its transponder off, '
        'or outside ADS-B coverage.',
        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      );
    } else if (a.onGround) {
      body = Text(
        '$reg is on the ground${_near != null ? ' at ${_near!.name}' : ''}'
        '${_distanceKm != null && _distanceKm! > 30 ? ', ${_distanceKm!.round()} km from ${widget.flight.departureAirportIata}' : ''}.',
        style: const TextStyle(fontSize: 13),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$reg is flying${a.callsign.isNotEmpty ? ' as ${a.callsign}' : ''}'
            '${_distanceKm != null ? ', ${_distanceKm!.round()} km from ${widget.flight.departureAirportIata}' : ''}.',
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            [
              if (a.altitudeFt != null) '${NumberFormat.decimalPattern().format(a.altitudeFt!.round())} ft',
              if (a.groundSpeedKt != null) '${a.groundSpeedKt!.round()} kt',
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => context.push('/cockpit', extra: {'hex': a.hex, 'callsign': a.callsign}),
            icon: const Icon(Icons.flight_takeoff, size: 16),
            label: const Text('Ride along'),
          ),
        ],
      );
    }

    return _ExtrasCard(
      icon: Icons.airplanemode_active,
      title: "Where's my plane",
      trailing: TextButton(onPressed: _editRegistration, child: Text(reg == null || reg.isEmpty ? 'Add' : 'Edit')),
      child: body,
    );
  }
}

// ── Leave for the airport ────────────────────────────────────────────────

class LeaveForAirportCard extends StatefulWidget {
  final Flight flight;
  const LeaveForAirportCard({super.key, required this.flight});

  @override
  State<LeaveForAirportCard> createState() => _LeaveForAirportCardState();
}

class _LeaveForAirportCardState extends State<LeaveForAirportCard> {
  DriveEstimate? _drive;
  String? _problem;
  bool _loading = false;

  Future<void> _plan() async {
    setState(() {
      _loading = true;
      _problem = null;
    });
    final departure = await AirportDirectory.instance.lookup(widget.flight.departureAirportIata);
    final here = await RoutingService.instance.currentPosition();
    if (departure == null) {
      _finish(problem: "We don't have coordinates for ${widget.flight.departureAirportIata}.");
      return;
    }
    if (here == null) {
      _finish(problem: 'Location is off or permission was declined.');
      return;
    }
    final drive = await RoutingService.instance.drive(here.latitude, here.longitude, departure.lat, departure.lon);
    _finish(drive: drive, problem: drive == null ? "Couldn't find a driving route from here." : null);
  }

  void _finish({DriveEstimate? drive, String? problem}) {
    if (!mounted) return;
    setState(() {
      _drive = drive;
      _problem = problem;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.flight;
    final cs = Theme.of(context).colorScheme;
    if (!f.scheduleIsKnown || f.bestDepartureTime.isBefore(DateTime.now())) return const SizedBox.shrink();

    final dep = AirportDirectory.instance.byIata(f.departureAirportIata);
    final arr = AirportDirectory.instance.byIata(f.arrivalAirportIata);
    final international = dep != null && arr != null && dep.countryCode != arr.countryCode;
    // Common airline guidance: 3h international, 2h domestic, before departure.
    final buffer = Duration(hours: international ? 3 : 2);

    Widget body;
    final drive = _drive;
    if (drive != null) {
      // OSRM ignores live traffic; pad it rather than pretend precision.
      final padded = Duration(minutes: (drive.duration.inMinutes * 1.25).round() + 10);
      final leaveBy = f.bestDepartureTime.subtract(buffer).subtract(padded);
      final late = leaveBy.isBefore(DateTime.now());
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            late ? 'Leave now' : 'Leave by ${DateFormat.jm().format(leaveBy)}',
            style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: late ? cs.error : cs.primary),
          ),
          Text(
            '${drive.distanceKm.toStringAsFixed(0)} km drive, about ${drive.duration.inMinutes} min without traffic '
            '(we allow ${padded.inMinutes}). Arriving ${buffer.inHours}h before an '
            '${international ? 'international' : 'domestic'} departure.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          Text('Routing: OpenStreetMap / OSRM', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      );
    } else {
      body = Row(
        children: [
          Expanded(
            child: Text(
              _problem ?? 'Work out when to leave based on your location and the drive.',
              style: TextStyle(fontSize: 13, color: _problem != null ? cs.error : cs.onSurfaceVariant),
            ),
          ),
          if (_loading)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            FilledButton.tonal(onPressed: _plan, child: const Text('Plan')),
        ],
      );
    }

    return _ExtrasCard(icon: Icons.directions_car_outlined, title: 'Getting to the airport', child: body);
  }
}

// ── Actions ───────────────────────────────────────────────────────────────

class FlightActionsRow extends StatelessWidget {
  final Flight flight;
  const FlightActionsRow({super.key, required this.flight});

  String? _liveLink() {
    final base = kIsWeb ? Uri.base.origin : AppConfig.publicWebUrl;
    if (base.isEmpty) return null;
    final callsign = flight.flightNumber.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return '$base/#/live/$callsign';
  }

  @override
  Widget build(BuildContext context) {
    final link = _liveLink();
    final landed = flight.status == FlightStatusEnum.landed || flight.bestArrivalTime.isBefore(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => Share.share(
              link != null
                  ? 'Follow ${flight.flightNumber} (${flight.routeDisplay}) live: $link'
                  : '${flight.flightNumber} ${flight.routeDisplay}',
            ),
            icon: const Icon(Icons.ios_share, size: 16),
            label: const Text('Share live link'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.push('/cockpit', extra: {'callsign': flight.flightNumber}),
            icon: const Icon(Icons.flight_takeoff, size: 16),
            label: const Text('Cockpit view'),
          ),
          if (landed)
            OutlinedButton.icon(
              onPressed: () => context.push('/flight/${flight.id}/replay', extra: flight),
              icon: const Icon(Icons.replay, size: 16),
              label: const Text('Replay flight'),
            ),
        ],
      ),
    );
  }
}

class _ExtrasCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  const _ExtrasCard({required this.icon, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.secondary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700))),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
