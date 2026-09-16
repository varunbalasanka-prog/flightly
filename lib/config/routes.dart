import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/models.dart';

import '../screens/auth/login_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/trips/trips_screen.dart';
import '../screens/trips/trip_detail_screen.dart';
import '../screens/flights/flight_search_screen.dart';
import '../screens/flights/manual_flight_screen.dart';
import '../screens/flights/flight_detail_screen.dart';
import '../screens/flights/live_map_screen.dart';
import '../screens/airport/airport_status_screen.dart';
import '../screens/connections/connection_screen.dart';
import '../screens/history/flight_history_screen.dart';
import '../screens/sharing/friends_screen.dart';
import '../screens/settings/settings_screen.dart';

/// GoRouter configuration for SkyPulse.
/// Uses shell route for bottom navigation persistence.
class AppRouter {
  AppRouter._();

  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  /// Mutable auth flag read by the redirect. The router itself is built once
  /// (see [instance]); rebuilding it per auth change threw away all navigation
  /// state and re-registered the same navigator GlobalKeys.
  static bool _isAuthenticated = false;
  static GoRouter? _instance;

  /// The single router for the app's lifetime.
  static GoRouter get instance => _instance ??= router(
        isAuthenticated: _isAuthenticated,
      );

  /// Updates the auth flag and re-runs the redirect on the live router.
  static void updateAuth({required bool isAuthenticated}) {
    if (_isAuthenticated == isAuthenticated) return;
    _isAuthenticated = isAuthenticated;
    _instance?.refresh();
  }

  static GoRouter router({required bool isAuthenticated}) {
    _isAuthenticated = isAuthenticated;
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: '/',
      redirect: (context, state) {
        final loggingIn = state.matchedLocation == '/login';

        if (!_isAuthenticated && !loggingIn) return '/login';
        if (_isAuthenticated && loggingIn) return '/';

        return null;
      },
      routes: [
        // Login (outside shell)
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),

        // Main app with bottom navigation shell
        ShellRoute(
          navigatorKey: _shellNavigatorKey,
          builder: (context, state, child) => HomeScreen(child: child),
          routes: [
            // Tab 1: Trips / Home
            GoRoute(
              path: '/',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: TripsScreen(),
              ),
              routes: [
                GoRoute(
                  path: 'trip/:tripId',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => TripDetailScreen(
                    tripId: state.pathParameters['tripId']!,
                  ),
                ),
                GoRoute(
                  path: 'flight/search',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const FlightSearchScreen(),
                ),
                GoRoute(
                  path: 'flight/manual',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const ManualFlightScreen(),
                ),
                GoRoute(
                  path: 'flight/:flightId',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => FlightDetailScreen(
                    flightId: state.pathParameters['flightId']!,
                    initialFlight: state.extra as Flight?,
                  ),
                ),
                GoRoute(
                  path: 'flight/:flightId/map',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => LiveMapScreen(
                    flightId: state.pathParameters['flightId']!,
                    flight: state.extra as Flight?,
                  ),
                ),
              ],
            ),

            // Tab 2: Flights / History
            GoRoute(
              path: '/history',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: FlightHistoryScreen(),
              ),
            ),

            // Tab 3: Map overview
            GoRoute(
              path: '/map',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: LiveMapScreen(),
              ),
            ),

            // Tab 4: Friends
            GoRoute(
              path: '/friends',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: FriendsScreen(),
              ),
            ),

            // Tab 5: Profile / Settings
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: SettingsScreen(),
              ),
            ),
          ],
        ),

        // Standalone routes (outside bottom nav)
        GoRoute(
          path: '/airport/:iataCode',
          builder: (context, state) => AirportStatusScreen(
            iataCode: state.pathParameters['iataCode']!,
          ),
        ),
        GoRoute(
          path: '/connection',
          builder: (context, state) {
            final extra = state.extra as Map<String, String>?;
            return ConnectionScreen(
              inboundFlightId: extra?['inboundFlightId'] ?? '',
              outboundFlightId: extra?['outboundFlightId'] ?? '',
            );
          },
        ),
      ],
    );
  }
}
