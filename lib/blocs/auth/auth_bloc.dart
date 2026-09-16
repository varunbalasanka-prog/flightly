import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import '../../config/app_config.dart';

// ── Events ──

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthGoogleSignInRequested extends AuthEvent {}

class AuthMagicLinkRequested extends AuthEvent {
  final String email;
  const AuthMagicLinkRequested(this.email);
  @override
  List<Object?> get props => [email];
}

class AuthSignOutRequested extends AuthEvent {}

class AuthStateChanged extends AuthEvent {
  final AuthState authState;
  const AuthStateChanged(this.authState);
  @override
  List<Object?> get props => [authState];
}

// ── States ──

abstract class AuthBlocState extends Equatable {
  const AuthBlocState();
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthBlocState {}

class AuthLoading extends AuthBlocState {}

class AuthAuthenticated extends AuthBlocState {
  final User user;
  const AuthAuthenticated(this.user);
  @override
  List<Object?> get props => [user.id];
}

class AuthUnauthenticated extends AuthBlocState {}

class AuthMagicLinkSent extends AuthBlocState {
  final String email;
  const AuthMagicLinkSent(this.email);
  @override
  List<Object?> get props => [email];
}

class AuthError extends AuthBlocState {
  final String message;
  const AuthError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── BLoC ──

/// Turns provider exceptions into something worth showing a user.
/// Previously the raw `e.toString()` was surfaced verbatim, so a mistyped
/// address produced "AuthApiException(message: Unable to validate email
/// address: invalid format, statusCode: 400, code: validation_failed)".
String _friendlyAuthError(Object error, String fallback) {
  if (error is AuthApiException) {
    final code = error.code;
    if (code == 'validation_failed') return 'That email address looks invalid.';
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit') {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (code == 'email_address_invalid') {
      return 'That email address looks invalid.';
    }
    return error.message;
  }
  return fallback;
}

class AuthBloc extends Bloc<AuthEvent, AuthBlocState> {
  final SupabaseClient _supabase;
  final GoogleSignIn _googleSignIn;
  StreamSubscription<AuthState>? _authSubscription;

  AuthBloc({
    required this._supabase,
    GoogleSignIn? googleSignIn,
  })  : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              clientId: kIsWeb ? AppConfig.googleWebClientId : null,
              serverClientId: kIsWeb ? null : AppConfig.googleWebClientId,
            ),
        super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthGoogleSignInRequested>(_onGoogleSignIn);
    on<AuthMagicLinkRequested>(_onMagicLink);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthStateChanged>(_onAuthStateChanged);

    // Listen to Supabase auth state changes
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      add(AuthStateChanged(data));
    });
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }

  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    final user = _supabase.auth.currentSession?.user;
    if (user != null) {
      emit(AuthAuthenticated(user));
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onGoogleSignIn(
    AuthGoogleSignInRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    emit(AuthLoading());
    try {
      if (kIsWeb) {
        // On Web, redirect back to the current web app origin
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: '${Uri.base.origin}/',
        );
        return;
      }

      final isMobile = defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android;

      if (!isMobile) {
        // For Desktop platforms (Windows/macOS/Linux), use Supabase's local loopback server
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: null,
        );
        return;
      }

      // For Native Mobile (Android/iOS), use google_sign_in for native UI
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        emit(AuthUnauthenticated());
        return;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        emit(const AuthError('Failed to get Google ID token'));
        return;
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      // Auth state change listener will emit AuthAuthenticated
    } catch (e) {
      emit(AuthError(
        _friendlyAuthError(e, 'Google sign-in failed. Please try again.'),
      ));
    }
  }

  Future<void> _onMagicLink(
    AuthMagicLinkRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _supabase.auth.signInWithOtp(
        email: event.email,
        emailRedirectTo:
            kIsWeb ? '${Uri.base.origin}/' : 'com.skypulse.app://login-callback/',
      );
      emit(AuthMagicLinkSent(event.email));
    } catch (e) {
      emit(AuthError(
        _friendlyAuthError(e, "Couldn't send the sign-in link. Please try again."),
      ));
    }
  }

  Future<void> _onSignOut(
    AuthSignOutRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    await _googleSignIn.signOut();
    await _supabase.auth.signOut();
    emit(AuthUnauthenticated());
  }

  void _onAuthStateChanged(
    AuthStateChanged event,
    Emitter<AuthBlocState> emit,
  ) {
    final session = event.authState.session;
    if (session != null) {
      emit(AuthAuthenticated(session.user));
    } else {
      // Only emit unauth if we're not in magic link sent state
      if (state is! AuthMagicLinkSent) {
        emit(AuthUnauthenticated());
      }
    }
  }
}
