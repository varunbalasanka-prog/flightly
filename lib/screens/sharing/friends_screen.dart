import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../blocs/flight/flight_bloc.dart';
import '../../blocs/sharing/sharing_bloc.dart';
import '../../config/app_config.dart';
import '../../models/models.dart';

/// Friends & flight sharing screen.
/// Allows users to enter friend invite codes to track their flights in real-time,
/// as well as generate and manage share codes for their own flights.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submitJoinCode() {
    final code = _codeController.text.trim().toUpperCase();
    // The length check and the message used to disagree (accepted 4, said 6)
    // and neither matched the codes the backend issues.
    if (code.length != AppConfig.inviteCodeLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enter the ${AppConfig.inviteCodeLength}-character invite code',
          ),
        ),
      );
      return;
    }
    context.read<SharingBloc>().add(JoinFlightRequested(code));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return BlocListener<SharingBloc, SharingState>(
      listener: (context, state) {
        if (state is JoinFlightSuccess) {
          _codeController.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('Flight joined successfully! Added to your Tracked Flights.'),
            ),
          );
          context.read<FlightBloc>().add(FlightLoadRequested());
        } else if (state is SharingFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text('Error: ${state.error}'),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Flight Sharing & Friends'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Join Shared Flight Card ──
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
              ),
              color: cs.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.group_add_outlined, color: cs.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Track a Friend\'s Flight',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              'Enter a ${AppConfig.inviteCodeLength}-character invite code',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeController,
                            textCapitalization: TextCapitalization.characters,
                            style: GoogleFonts.sourceCodePro(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                            decoration: InputDecoration(
                              hintText: 'e.g. SKY789',
                              filled: true,
                              fillColor: cs.surfaceContainerHigh,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            onSubmitted: (_) => _submitJoinCode(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        BlocBuilder<SharingBloc, SharingState>(
                          builder: (context, state) {
                            final isLoading = state is SharingInProgress;
                            return FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: isLoading ? null : _submitJoinCode,
                              child: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Track'),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Share Your Flights Section ──
            Text(
              'SHARE YOUR FLIGHTS',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),

            BlocBuilder<FlightBloc, FlightState>(
              builder: (context, flightState) {
                if (flightState is FlightLoadSuccess && flightState.flights.isNotEmpty) {
                  return Column(
                    children: flightState.flights.map((flight) {
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        color: cs.surfaceContainer,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.flight, color: cs.primary, size: 20),
                          ),
                          title: Text(
                            '${flight.flightNumber} · ${flight.departureAirportIata} → ${flight.arrivalAirportIata}',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          subtitle: Text(
                            'Status: ${flight.status.name.toUpperCase()} · ${flight.airlineName ?? flight.airlineIata}',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                          trailing: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            icon: const Icon(Icons.share, size: 16),
                            label: const Text('Share Code'),
                            onPressed: () => _showFlightShareSheet(context, flight),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }

                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.flight_outlined, size: 36, color: cs.primary.withValues(alpha: 0.7)),
                      const SizedBox(height: 12),
                      Text(
                        'No tracked flights to share yet',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Once you add upcoming flights to SkyPulse, you can instantly create secure invite codes for family and friends.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: () => context.push('/flight/search'),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Flight to Track'),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // ── Why Share Info Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: cs.primary, size: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Private & Real-Time Sync',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sharing codes are encrypted and grant view-only live telemetry access to your friend until flight arrival.',
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFlightShareSheet(BuildContext context, Flight flight) {
    context.read<SharingBloc>().add(ShareCodeRequested(flight.id));

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final cs = Theme.of(sheetCtx).colorScheme;
        return BlocBuilder<SharingBloc, SharingState>(
          builder: (context, shareState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Share ${flight.flightNumber}',
                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Send this code to your friends or family:',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    if (shareState is SharingInProgress)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )
                    else if (shareState is ShareCodeSuccess) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          shareState.code,
                          style: GoogleFonts.sourceCodePro(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: shareState.code));
                          ScaffoldMessenger.of(sheetCtx).showSnackBar(
                            const SnackBar(content: Text('Invite code copied to clipboard!')),
                          );
                          Navigator.pop(sheetCtx);
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy Code'),
                      ),
                    ] else if (shareState is SharingFailure) ...[
                      Text('Error: ${shareState.error}', style: TextStyle(color: cs.error)),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
