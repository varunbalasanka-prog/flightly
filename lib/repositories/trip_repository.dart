import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../models/models.dart';

class TripRepository {
  final SupabaseClient _supabase;

  TripRepository({required this._supabase});

  Future<List<Trip>> getTrips() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final response = await _supabase
          .from('trips')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      return (response as List).map((json) => Trip.fromJson(json)).toList();
    } catch (e) {
      debugPrint('TripRepository.getTrips error: $e');
      return [];
    }
  }

  Stream<List<Trip>> streamTrips() {
    final user = _supabase.auth.currentUser;
    if (user == null) return Stream.value([]);

    return _supabase
        .from('trips')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((json) => Trip.fromJson(json)).toList());
  }

  Future<Trip> createTrip(String name) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in to create a trip');
    }

    final response = await _supabase
        .from('trips')
        .insert({
          'name': name.trim(),
          'user_id': user.id,
        })
        .select()
        .single();

    return Trip.fromJson(response);
  }

  Future<void> deleteTrip(String tripId) async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      await _supabase
          .from('trips')
          .delete()
          .eq('id', tripId)
          .eq('user_id', user.id);
    }
  }
}
