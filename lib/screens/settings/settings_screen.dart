import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/quota/quota_bloc.dart';
import '../../config/app_config.dart';

/// Settings / Profile screen with quota display.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Profile Card ──
          BlocBuilder<AuthBloc, AuthBlocState>(
            builder: (context, state) {
              final email = state is AuthAuthenticated
                  ? state.user.email ?? 'Unknown'
                  : 'Not signed in';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: cs.surfaceContainerHigh,
                        child: Icon(Icons.person_outline,
                            color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              email,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              'SkyPulse Beta Tester',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── Quota Dashboard ──
          Text(
            'API QUOTA',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          _QuotaCard(cs: cs),
          const SizedBox(height: 24),

          // ── Preferences ──
          Text(
            'PREFERENCES',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                // Both of these were live-looking switches wired to `(v) {}`:
                // permanently on, and silently doing nothing when tapped.
                // Until theme switching and push delivery are actually
                // implemented, show them as explicitly unavailable rather
                // than pretending they work.
                const SwitchListTile(
                  title: Text('Dark Mode'),
                  subtitle: Text('SkyPulse is dark-only in this beta'),
                  value: true,
                  onChanged: null,
                  secondary: Icon(Icons.dark_mode_outlined),
                ),
                const Divider(height: 1),
                const SwitchListTile(
                  title: Text('Push Notifications'),
                  subtitle: Text('Not available yet in this beta'),
                  value: false,
                  onChanged: null,
                  secondary: Icon(Icons.notifications_off_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── About ──
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About'),
                  subtitle: Text('v${AppConfig.appVersion}'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Sign Out ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  context.read<AuthBloc>().add(AuthSignOutRequested()),
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  final ColorScheme cs;
  const _QuotaCard({required this.cs});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QuotaBloc, QuotaState>(
      builder: (context, state) {
        int used = 0;
        int limit = 100;

        if (state is QuotaLoadSuccess) {
          used = state.quota.globalRequestsUsed;
          limit = state.quota.globalRequestsLimit;
        }

        final percent = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          color: cs.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.speed, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Monthly Flight Radar Quota',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$used / $limit',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 8,
                    backgroundColor: cs.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation(
                      percent > 0.8
                          ? cs.error
                          : percent > 0.5
                              ? cs.tertiary
                              : cs.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(limit - used).clamp(0, limit)} requests remaining',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Free OpenSky Tier',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
