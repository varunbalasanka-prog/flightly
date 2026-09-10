import 'package:flutter/material.dart';

class TripDetailScreen extends StatelessWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Trip Details')),
      body: Center(
        child: Text('Trip: $tripId', style: TextStyle(color: cs.onSurface)),
      ),
    );
  }
}
