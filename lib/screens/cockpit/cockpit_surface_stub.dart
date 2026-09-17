import 'package:flutter/widgets.dart';

typedef CockpitSend = void Function(Map<String, dynamic> message);

/// Fallback for platforms with neither a browser nor a native web view.
class CockpitSurface extends StatelessWidget {
  final void Function(CockpitSend send) onReady;
  const CockpitSurface({super.key, required this.onReady});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Cockpit view is not available on this platform.'));
}
