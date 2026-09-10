import 'package:flutter_bloc/flutter_bloc.dart';
import '../../repositories/sharing_repository.dart';

// --- Events ---
abstract class SharingEvent {}

class ShareCodeRequested extends SharingEvent {
  final String flightId;
  ShareCodeRequested(this.flightId);
}

class JoinFlightRequested extends SharingEvent {
  final String inviteCode;
  JoinFlightRequested(this.inviteCode);
}

// --- States ---
abstract class SharingState {}

class SharingInitial extends SharingState {}
class SharingInProgress extends SharingState {}
class ShareCodeSuccess extends SharingState {
  final String code;
  ShareCodeSuccess(this.code);
}
class JoinFlightSuccess extends SharingState {}
class SharingFailure extends SharingState {
  final String error;
  SharingFailure(this.error);
}

// --- BLoC ---
class SharingBloc extends Bloc<SharingEvent, SharingState> {
  final SharingRepository _repository;

  SharingBloc({required this._repository})
      : super(SharingInitial()) {
    on<ShareCodeRequested>(_onShareCodeRequested);
    on<JoinFlightRequested>(_onJoinRequested);
  }

  Future<void> _onShareCodeRequested(
      ShareCodeRequested event, Emitter<SharingState> emit) async {
    emit(SharingInProgress());
    try {
      final code = await _repository.generateShareCode(event.flightId);
      emit(ShareCodeSuccess(code));
    } catch (e) {
      emit(SharingFailure(e.toString()));
    }
  }

  Future<void> _onJoinRequested(
      JoinFlightRequested event, Emitter<SharingState> emit) async {
    emit(SharingInProgress());
    try {
      await _repository.joinSharedFlight(event.inviteCode);
      emit(JoinFlightSuccess());
    } catch (e) {
      emit(SharingFailure(e.toString()));
    }
  }
}
