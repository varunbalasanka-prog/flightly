import 'package:supabase_flutter/supabase_flutter.dart';

class SharingRepository {
  final SupabaseClient _supabase;

  SharingRepository({required this._supabase});

  Future<String> generateShareCode(String flightId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Must be logged in to share flights');

    // Share codes are issued only by the share-flight Edge Function, which
    // verifies the caller actually owns the flight and uses a CSPRNG. The old
    // client-side fallback inserted straight into `flight_shares` with a
    // Random() code and no ownership check, so a user could mint an invite for
    // a flight belonging to someone else and hand it to a second account.
    final response = await _supabase.functions.invoke(
      'share-flight',
      body: {'flightId': flightId},
    );

    final data = response.data as Map<String, dynamic>?;
    final code = data?['inviteCode'] as String?;

    if (response.status != 200 || code == null) {
      throw Exception(data?['error'] as String? ?? 'Could not create a share code');
    }
    return code;
  }

  Future<void> joinSharedFlight(String inviteCode) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Must be logged in to join flights');

    final cleanCode = inviteCode.toUpperCase().trim();

    // Redeeming is done only through the join_shared_flight RPC, which checks
    // the code is pending, unclaimed and not the caller's own. The previous
    // direct-table fallback re-pointed any matching share row at the current
    // user -- the exact privilege escalation the RLS policies now prevent, so
    // it would silently fail here anyway.
    final result = await _supabase.rpc(
      'join_shared_flight',
      params: {'code': cleanCode},
    ) as Map<String, dynamic>?;

    if (result?['success'] != true) {
      throw Exception(
        result?['error'] as String? ?? 'Invalid or expired invite code',
      );
    }
  }
}
