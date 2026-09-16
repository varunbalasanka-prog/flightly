import 'package:flutter/material.dart';
import '../../config/app_config.dart';

class StaleDataBanner extends StatelessWidget {
  final DateTime lastUpdated;
  
  const StaleDataBanner({
    super.key,
    required this.lastUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final difference = DateTime.now().difference(lastUpdated);
    final isStale = difference.inMinutes > AppConfig.staleDataThresholdMinutes;

    if (!isStale) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.shade800,
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline mode. Data is ${difference.inMinutes} minutes old.',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
