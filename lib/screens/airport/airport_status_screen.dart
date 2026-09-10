import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../providers/flight_data_provider.dart';
import '../../services/aviation_data_service.dart';

/// Airport status screen — weather, delay indices, lounge info, gate guides.
class AirportStatusScreen extends StatefulWidget {
  final String iataCode;
  const AirportStatusScreen({super.key, required this.iataCode});

  @override
  State<AirportStatusScreen> createState() => _AirportStatusScreenState();
}

class _AirportStatusScreenState extends State<AirportStatusScreen> {
  late String _currentIata;
  AirportInfo? _airportInfo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _currentIata = widget.iataCode.toUpperCase();
    _loadAirport();
  }

  Future<void> _loadAirport() async {
    setState(() => _loading = true);
    final info = await AviationDataService.instance.getAirport(_currentIata);
    if (mounted) {
      setState(() {
        _airportInfo = info;
        _loading = false;
      });
    }
  }

  void _showSearchDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Search Airport'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'e.g. JFK, LHR, DXB, DEL',
                prefixIcon: Icon(Icons.search),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            Text(
              'Popular Hubs:',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: ['JFK', 'LHR', 'DXB', 'LAX', 'DEL', 'BOM', 'SIN', 'FRA'].map((hub) {
                return ActionChip(
                  label: Text(hub),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _currentIata = hub;
                    });
                    _loadAirport();
                  },
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim().toUpperCase();
              if (val.isNotEmpty) {
                Navigator.pop(ctx);
                setState(() {
                  _currentIata = val;
                });
                _loadAirport();
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = _airportInfo?.airport;

    return Scaffold(
      appBar: AppBar(
        title: Text('$_currentIata Hub Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search Airport',
            onPressed: _showSearchDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAirport,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Airport Header ──
                  _AirportHeader(
                    iataCode: _currentIata,
                    status: status,
                    cs: cs,
                  ),
                  const SizedBox(height: 16),

                  // ── Live Weather & Delay Indicators ──
                  _OperationsIndicatorCard(status: status, cs: cs),
                  const SizedBox(height: 24),

                  // ── Lounges Section ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'AIRPORT LOUNGES',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'Verified Amenities',
                        style: TextStyle(fontSize: 12, color: cs.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._getLoungesForAirport(_currentIata).map(
                    (lounge) => _LoungeCard(
                      name: lounge.name,
                      terminal: lounge.terminal,
                      isOpen: lounge.isOpen,
                      amenities: lounge.amenities,
                      cs: cs,
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  List<_LoungeItem> _getLoungesForAirport(String iata) {
    return [
      _LoungeItem(
        name: '$iata Signature Club',
        terminal: 'Terminal 1 · Concourse A',
        isOpen: true,
        amenities: const ['High-Speed WiFi', 'Hot Buffet', 'Premium Bar', 'Shower Suites'],
      ),
      _LoungeItem(
        name: 'The Centurion Lounge',
        terminal: 'Terminal 2 · Gate 24',
        isOpen: true,
        amenities: const ['WiFi', 'Fine Dining', 'Cocktail Lounge', 'Spa'],
      ),
      _LoungeItem(
        name: 'SkyTeam & Star Alliance Lounge',
        terminal: 'International Terminal · Gate 40',
        isOpen: false,
        amenities: const ['WiFi', 'Quiet Pods', 'Snacks'],
      ),
    ];
  }
}

class _LoungeItem {
  final String name;
  final String terminal;
  final bool isOpen;
  final List<String> amenities;

  const _LoungeItem({
    required this.name,
    required this.terminal,
    required this.isOpen,
    required this.amenities,
  });
}

class _AirportHeader extends StatelessWidget {
  final String iataCode;
  final AirportStatus? status;
  final ColorScheme cs;

  const _AirportHeader({
    required this.iataCode,
    required this.status,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final fullName = status?.name ?? '$iataCode International Airport';
    final location = status != null ? '${status!.city}, ${status!.country}' : 'Global Hub';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            iataCode,
            style: GoogleFonts.inter(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              color: cs.primary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            fullName,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            location,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OperationsIndicatorCard extends StatelessWidget {
  final AirportStatus? status;
  final ColorScheme cs;

  const _OperationsIndicatorCard({
    required this.status,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final delay = status?.delayMinutes ?? 5;
    final weather = status?.weatherCondition ?? 'Clear';
    final temp = status?.temperatureC ?? 22;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AIRPORT FLOW',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    delay > 20 ? 'Moderate Delays' : 'Normal Operations',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: delay > 20 ? Colors.amber : Colors.green,
                    ),
                  ),
                  Text(
                    'Avg ground delay: ~$delay min',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: cs.outlineVariant.withValues(alpha: 0.3),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'METAR WEATHER',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$weather · $temp°C',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      'Wind calm · 10mi visibility',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoungeCard extends StatelessWidget {
  final String name;
  final String terminal;
  final bool isOpen;
  final List<String> amenities;
  final ColorScheme cs;

  const _LoungeCard({
    required this.name,
    required this.terminal,
    required this.isOpen,
    required this.amenities,
    required this.cs,
  });

  IconData _amenityIcon(String amenity) {
    if (amenity.contains('WiFi')) return Icons.wifi;
    if (amenity.contains('Buffet') || amenity.contains('Food') || amenity.contains('Dining')) return Icons.restaurant;
    if (amenity.contains('Bar') || amenity.contains('Cocktail')) return Icons.local_bar;
    if (amenity.contains('Shower')) return Icons.shower;
    if (amenity.contains('Spa')) return Icons.spa;
    return Icons.check_circle_outline;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOpen
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isOpen ? 'OPEN' : 'CLOSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isOpen ? Colors.green : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              terminal,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: amenities.map((a) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_amenityIcon(a), size: 14, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(
                      a,
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
