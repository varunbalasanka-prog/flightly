import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/models.dart';
import '../../repositories/trip_repository.dart';

// --- Events ---
abstract class TripEvent {}

/// Subscribe to the live trip list.
class TripSubscriptionRequested extends TripEvent {}

/// One-shot fetch, for pull-to-refresh or when realtime is unavailable.
class TripLoadRequested extends TripEvent {}

class TripCreateRequested extends TripEvent {
  final String name;
  TripCreateRequested(this.name);
}

class TripDeleteRequested extends TripEvent {
  final String tripId;
  TripDeleteRequested(this.tripId);
}

// --- States ---
abstract class TripState {}

class TripInitial extends TripState {}
class TripLoadInProgress extends TripState {}
class TripLoadSuccess extends TripState {
  final List<Trip> trips;
  TripLoadSuccess(this.trips);
}
class TripLoadFailure extends TripState {
  final String error;
  TripLoadFailure(this.error);
}

// --- BLoC ---
class TripBloc extends Bloc<TripEvent, TripState> {
  final TripRepository _repository;

  TripBloc({required this._repository})
      : super(TripInitial()) {
    on<TripSubscriptionRequested>(_onSubscriptionRequested);
    on<TripLoadRequested>(_onLoadRequested);
    on<TripCreateRequested>(_onCreateRequested);
    on<TripDeleteRequested>(_onDeleteRequested);
  }

  Future<void> _onSubscriptionRequested(
      TripSubscriptionRequested event, Emitter<TripState> emit) async {
    emit(TripLoadInProgress());

    // emit.forEach holds the handler open for the life of the stream, so the
    // subscription is torn down with the bloc.
    await emit.forEach<List<Trip>>(
      _repository.streamTrips(),
      onData: TripLoadSuccess.new,
      onError: (_, _) =>
          TripLoadFailure("Couldn't load your trips. Pull to refresh."),
    );
  }

  Future<void> _onLoadRequested(
      TripLoadRequested event, Emitter<TripState> emit) async {
    if (state is! TripLoadSuccess) emit(TripLoadInProgress());
    try {
      emit(TripLoadSuccess(await _repository.getTrips()));
    } catch (_) {
      emit(TripLoadFailure("Couldn't load your trips. Please try again."));
    }
  }

  Future<void> _onCreateRequested(
      TripCreateRequested event, Emitter<TripState> emit) async {
    try {
      await _repository.createTrip(event.name);
      add(TripLoadRequested());
    } catch (e) {
      emit(TripLoadFailure('Failed to create trip: $e'));
    }
  }

  Future<void> _onDeleteRequested(
      TripDeleteRequested event, Emitter<TripState> emit) async {
    try {
      await _repository.deleteTrip(event.tripId);
      add(TripLoadRequested());
    } catch (e) {
      emit(TripLoadFailure('Failed to delete trip: $e'));
    }
  }
}
