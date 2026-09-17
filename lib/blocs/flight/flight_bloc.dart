import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/models.dart';
import '../../repositories/flight_repository.dart';

/// The user's tracked flights.
///
/// Backed by a Supabase realtime subscription, so status changes written by the
/// poll-flights function reach the UI without a manual refresh. Provider
/// lookups live in `FlightLookupBloc`; they previously shared this state union,
/// which made the two fight over the same screen.

// --- Events ---
abstract class FlightEvent {}

/// Subscribe to the live flight list. Emits on every change.
class FlightSubscriptionRequested extends FlightEvent {}

/// One-shot fetch, for pull-to-refresh or when realtime is unavailable.
class FlightLoadRequested extends FlightEvent {}

class FlightAddRequested extends FlightEvent {
  final Flight flight;
  FlightAddRequested(this.flight);
}

class FlightDeleteRequested extends FlightEvent {
  final String flightId;
  FlightDeleteRequested(this.flightId);
}

// --- States ---
abstract class FlightState {}

class FlightInitial extends FlightState {}

class FlightLoadInProgress extends FlightState {}

class FlightLoadSuccess extends FlightState {
  final List<Flight> flights;
  FlightLoadSuccess(this.flights);
}

class FlightLoadFailure extends FlightState {
  final String error;
  FlightLoadFailure(this.error);
}

// --- BLoC ---
class FlightBloc extends Bloc<FlightEvent, FlightState> {
  final FlightRepository _repository;

  FlightBloc({required this._repository}) : super(FlightInitial()) {
    on<FlightSubscriptionRequested>(_onSubscriptionRequested);
    on<FlightLoadRequested>(_onLoadRequested);
    on<FlightAddRequested>(_onAddRequested);
    on<FlightDeleteRequested>(_onDeleteRequested);
  }

  Future<void> _onSubscriptionRequested(
    FlightSubscriptionRequested event,
    Emitter<FlightState> emit,
  ) async {
    emit(FlightLoadInProgress());

    // emit.forEach keeps the handler alive for the life of the stream, so the
    // subscription is cancelled automatically when the bloc closes.
    await emit.forEach<List<Flight>>(
      _repository.streamFlights(),
      onData: FlightLoadSuccess.new,
      onError: (_, _) =>
          FlightLoadFailure("Couldn't load your flights. Pull to refresh."),
    );
  }

  Future<void> _onLoadRequested(
    FlightLoadRequested event,
    Emitter<FlightState> emit,
  ) async {
    if (state is! FlightLoadSuccess) emit(FlightLoadInProgress());
    try {
      emit(FlightLoadSuccess(await _repository.getFlights()));
    } catch (_) {
      emit(FlightLoadFailure("Couldn't load your flights. Please try again."));
    }
  }

  /// Saves a flight and completes only once the write succeeds, so callers can
  /// report the real outcome instead of assuming it.
  Future<Flight> addFlight(Flight flight) async {
    final saved = await _repository.addFlight(flight);
    add(FlightLoadRequested());
    return saved;
  }

  /// Persists changes to a tracked flight (chosen radio station, tail number,
  /// schedule times) and completes once the write succeeds.
  Future<void> updateFlight(Flight flight) async {
    await _repository.updateFlight(flight);
    add(FlightLoadRequested());
  }

  Future<void> _onAddRequested(
    FlightAddRequested event,
    Emitter<FlightState> emit,
  ) async {
    try {
      await _repository.addFlight(event.flight);
      // The realtime stream delivers the new row; refresh only as a fallback
      // for when no subscription is active.
      add(FlightLoadRequested());
    } catch (e) {
      emit(FlightLoadFailure('Failed to add flight: $e'));
    }
  }

  Future<void> _onDeleteRequested(
    FlightDeleteRequested event,
    Emitter<FlightState> emit,
  ) async {
    try {
      await _repository.deleteFlight(event.flightId);
      add(FlightLoadRequested());
    } catch (e) {
      emit(FlightLoadFailure('Failed to remove flight: $e'));
    }
  }
}
