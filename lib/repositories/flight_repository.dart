import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../models/models.dart';
import '../../providers/flight_data_provider.dart';

class FlightRepository {
  final SupabaseClient _supabase;
  final FlightDataProvider _provider;

  FlightRepository({
    required this._supabase,
    required this._provider,
  });

  /// Fetch all flights for the current authenticated user.
  Future<List<Flight>> getFlights() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final response = await _supabase
          .from('flights')
          .select()
          .eq('user_id', user.id)
          .order('scheduled_departure', ascending: true);

      return (response as List).map((json) => Flight.fromJson(json)).toList();
    } catch (e) {
      debugPrint('FlightRepository.getFlights error: $e');
      return [];
    }
  }

  /// Realtime stream of user's flights.
  Stream<List<Flight>> streamFlights() {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _supabase
        .from('flights')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('scheduled_departure', ascending: true)
        .map((rows) => rows.map((json) => Flight.fromJson(json)).toList());
  }

  /// Search flight by flight number or route.
  Future<FlightLookupResult> lookupFlight(String flightQuery, {DateTime? date}) async {
    return _provider.searchFlight(flightQuery, date: date);
  }

  /// Save flight into Supabase database and activate monitoring.
  Future<Flight> addFlight(Flight flight) async {
    final user = _supabase.auth.currentUser;
    final flightJson = flight.toJson();

    if (user != null) {
      flightJson['user_id'] = user.id;
    }

    // Insert into Supabase
    final response = await _supabase
        .from('flights')
        .insert(flightJson)
        .select()
        .single();

    final savedFlight = Flight.fromJson(response);

    // Setup background monitoring
    try {
      await _provider.setupMonitoring(savedFlight.id);
    } catch (e) {
      debugPrint('Warning: monitor setup failed: $e');
    }

    return savedFlight;
  }

  /// Delete a flight by ID.
  Future<void> deleteFlight(String flightId) async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      await _supabase
          .from('flights')
          .delete()
          .eq('id', flightId)
          .eq('user_id', user.id);
    }
  }

  /// Update flight details (e.g. associate with trip).
  Future<void> updateFlight(Flight flight) async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      await _supabase
          .from('flights')
          .update(flight.toJson())
          .eq('id', flight.id)
          .eq('user_id', user.id);
    }
  }

  /// Get flights associated with a specific trip.
  Future<List<Flight>> getFlightsForTrip(String tripId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final response = await _supabase
          .from('flights')
          .select()
          .eq('user_id', user.id)
          .eq('trip_id', tripId)
          .order('scheduled_departure', ascending: true);

      return (response as List).map((json) => Flight.fromJson(json)).toList();
    } catch (e) {
      debugPrint('FlightRepository.getFlightsForTrip error: $e');
      return [];
    }
  }
}
