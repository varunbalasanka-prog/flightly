import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LiveUpdatesPausedBanner extends StatelessWidget {
  const LiveUpdatesPausedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: cs.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.pause_circle_outline, color: cs.onErrorContainer, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live Updates Paused',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Monthly API limit reached for the private beta.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
