import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../blocs/quota/quota_bloc.dart';

class QuotaIndicator extends StatelessWidget {
  const QuotaIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QuotaBloc, QuotaState>(
      builder: (context, state) {
        if (state is QuotaLoadSuccess) {
          final globalUsed = state.quota.globalRequestsUsed;
          final globalLimit = state.quota.globalRequestsLimit;
          final percent = globalUsed / globalLimit;
          final cs = Theme.of(context).colorScheme;

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed, size: 18, color: cs.secondary),
                      const SizedBox(width: 8),
                      Text(
                        'Global Beta Quota',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$globalUsed / $globalLimit',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                          fontFeatures: [const FontFeature.tabularFigures()],
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
                ],
              ),
            ),
          );
        }
        // Fallback for loading/initial state
        return const SizedBox.shrink();
      },
    );
  }
}
