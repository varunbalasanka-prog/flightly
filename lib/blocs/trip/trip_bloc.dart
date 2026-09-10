import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/models.dart';
import '../../repositories/trip_repository.dart';

// --- Events ---
abstract class TripEvent {}

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
    on<TripLoadRequested>(_onLoadRequested);
    on<TripCreateRequested>(_onCreateRequested);
    on<TripDeleteRequested>(_onDeleteRequested);
  }

  Future<void> _onLoadRequested(
      TripLoadRequested event, Emitter<TripState> emit) async {
    emit(TripLoadInProgress());
    try {
      final trips = await _repository.getTrips();
      emit(TripLoadSuccess(trips));
    } catch (e) {
      emit(TripLoadFailure(e.toString()));
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
