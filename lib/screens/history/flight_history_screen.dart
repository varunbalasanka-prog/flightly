import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Flight history with passport map and stats — matches Stitch
/// "My Flight Log & Stats" and "Flighty Passport Share" designs.
class FlightHistoryScreen extends StatefulWidget {
  const FlightHistoryScreen({super.key});

  @override
  State<FlightHistoryScreen> createState() => _FlightHistoryScreenState();
}

class _FlightHistoryScreenState extends State<FlightHistoryScreen> {
  int _selectedYear = 0; // 0 = All Time

  final _years = ['ALL', '2026', '2025', '2024', '2023'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: () {},
            tooltip: 'Share Passport',
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ── Year Filter Chips ──
          SliverToBoxAdapter(
            child: SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _years.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => ChoiceChip(
                  label: Text(_years[i]),
                  selected: _selectedYear == i,
                  onSelected: (v) => setState(() => _selectedYear = i),
                  selectedColor: cs.primary.withValues(alpha: 0.2),
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _selectedYear == i ? cs.primary : cs.onSurfaceVariant,
                  ),
                  showCheckmark: false,
                  side: BorderSide(
                    color: _selectedYear == i
                        ? cs.primary.withValues(alpha: 0.3)
                        : cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),

          // ── Passport Map ──
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
              ),
              clipBehavior: Clip.antiAlias,
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(30, -30),
                  initialZoom: 2.0,
                  interactionOptions: InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: isDark
                        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
                        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                  ),
                  // Demo route lines
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [
                          const LatLng(32.89, -97.04), // DFW
                          const LatLng(38.85, -77.04), // DCA
                        ],
                        color: cs.secondary.withValues(alpha: 0.6),
                        strokeWidth: 1.5,
                      ),
                      Polyline(
                        points: [
                          const LatLng(32.89, -97.04), // DFW
                          const LatLng(35.76, 140.38), // NRT
                        ],
                        color: cs.secondary.withValues(alpha: 0.6),
                        strokeWidth: 1.5,
                      ),
                      Polyline(
                        points: [
                          const LatLng(32.89, -97.04), // DFW
                          const LatLng(51.47, -0.46),  // LHR
                        ],
                        color: cs.secondary.withValues(alpha: 0.6),
                        strokeWidth: 1.5,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Stats Grid (matching Stitch design) ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatTile(value: '189,194', label: 'Miles', cs: cs),
                  const SizedBox(width: 8),
                  _StatTile(value: '312', label: 'Flights', cs: cs),
                  const SizedBox(width: 8),
                  _StatTile(value: '47', label: 'Airports', cs: cs),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatTile(value: '23', label: 'Countries', cs: cs),
                  const SizedBox(width: 8),
                  _StatTile(value: '642h', label: 'Airtime', cs: cs),
                  const SizedBox(width: 8),
                  _StatTile(value: '18%', label: 'Delayed', cs: cs),
                ],
              ),
            ),
          ),

          // ── Recent Flights ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text(
                'RECENT FLIGHTS',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final flights = [
                  ('AA 472', 'DFW → DCA', 'Jan 21', 'On Time'),
                  ('JL 061', 'DFW → NRT', 'Jan 15', 'Delayed'),
                  ('BA 192', 'DFW → LHR', 'Jan 3', 'On Time'),
                  ('UA 348', 'DCA → BOS', 'Dec 28', 'On Time'),
                  ('DL 977', 'ATL → LAX', 'Dec 20', 'Delayed'),
                ];
                final (number, route, date, status) = flights[index];
                final isDelayed = status == 'Delayed';

                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    leading: Icon(Icons.flight,
                        color: cs.secondary, size: 20),
                    title: Text(
                      '$number  $route',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    subtitle: Text(date,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDelayed
                            ? cs.error.withValues(alpha: 0.15)
                            : cs.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDelayed ? cs.error : cs.primary,
                        ),
                      ),
                    ),
                  ),
                );
              },
              childCount: 5,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final ColorScheme cs;
  const _StatTile({required this.value, required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
