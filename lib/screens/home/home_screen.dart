import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Home screen shell with bottom navigation.
/// Wraps GoRouter's ShellRoute child for persistent bottom nav.
class HomeScreen extends StatelessWidget {
  final Widget child;
  const HomeScreen({super.key, required this.child});

  static const _tabs = [
    (icon: Icons.card_travel_rounded, label: 'Trips'),
    (icon: Icons.flight_rounded, label: 'Flights'),
    (icon: Icons.public, label: 'World'),
    (icon: Icons.people_outline_rounded, label: 'Friends'),
    (icon: Icons.person_outline_rounded, label: 'Profile'),
  ];

  static const _tabPaths = ['/', '/history', '/map', '/friends', '/settings'];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _tabPaths.indexWhere((p) => location.startsWith(p) && p != '/');
    return index >= 0 ? index : 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          context.go(_tabPaths[index]);
        },
        destinations: _tabs
            .map((tab) => NavigationDestination(
                  icon: Icon(tab.icon),
                  label: tab.label,
                ))
            .toList(),
      ),
    );
  }
}
