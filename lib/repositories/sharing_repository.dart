import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/models.dart';

class SharingRepository {
  final SupabaseClient _supabase;

  SharingRepository({required this._supabase});

  Future<String> generateShareCode(String flightId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Must be logged in to share flights');

    try {
      // 1. Try Edge function if available
      final response = await _supabase.functions.invoke(
        'share-flight',
        body: {'flightId': flightId},
      ).timeout(const Duration(seconds: 3));

      if (response.status == 200 && response.data != null && response.data['inviteCode'] != null) {
        return response.data['inviteCode'] as String;
      }
    } catch (_) {}

    // 2. Direct database generation fallback
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    final code = List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();

    await _supabase.from('flight_shares').insert({
      'flight_id': flightId,
      'owner_id': user.id,
      'invite_code': code,
      'status': 'pending',
    });

    return code;
  }

  Future<void> joinSharedFlight(String inviteCode) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Must be logged in to join flights');

    final cleanCode = inviteCode.toUpperCase().trim();

    // 1. Try RPC join_shared_flight
    try {
      final rpcRes = await _supabase.rpc('join_shared_flight', params: {'code': cleanCode});
      if (rpcRes != null && rpcRes['success'] == true) {
        return;
      }
    } catch (_) {}

    // 2. Direct database query
    final shareResponse = await _supabase
        .from('flight_shares')
        .select()
        .eq('invite_code', cleanCode)
        .maybeSingle();

    if (shareResponse == null) {
      throw Exception('Invalid or expired invite code');
    }

    final share = FlightShare.fromJson(shareResponse);

    await _supabase
        .from('flight_shares')
        .update({
          'shared_with_id': user.id,
          'status': 'accepted',
        })
        .eq('id', share.id);
  }
}
