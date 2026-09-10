import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/models.dart';
import '../../providers/flight_data_provider.dart';
import '../../repositories/flight_repository.dart';

// --- Events ---
abstract class FlightEvent {}

class FlightLoadRequested extends FlightEvent {}

class FlightLookupRequested extends FlightEvent {
  final String flightIata;
  FlightLookupRequested(this.flightIata);
}

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

class FlightLookupInProgress extends FlightState {}
class FlightLookupSuccess extends FlightState {
  final FlightLookupResult result;
  FlightLookupSuccess(this.result);
}
class FlightLookupFailure extends FlightState {
  final String error;
  FlightLookupFailure(this.error);
}

// --- BLoC ---
class FlightBloc extends Bloc<FlightEvent, FlightState> {
  final FlightRepository _repository;

  FlightBloc({required this._repository})
      : super(FlightInitial()) {
    on<FlightLoadRequested>(_onLoadRequested);
    on<FlightLookupRequested>(_onLookupRequested);
    on<FlightAddRequested>(_onAddRequested);
    on<FlightDeleteRequested>(_onDeleteRequested);
  }

  Future<void> _onLoadRequested(
      FlightLoadRequested event, Emitter<FlightState> emit) async {
    emit(FlightLoadInProgress());
    try {
      final flights = await _repository.getFlights();
      emit(FlightLoadSuccess(flights));
    } catch (e) {
      emit(FlightLoadFailure(e.toString()));
    }
  }

  Future<void> _onLookupRequested(
      FlightLookupRequested event, Emitter<FlightState> emit) async {
    emit(FlightLookupInProgress());
    try {
      final result = await _repository.lookupFlight(event.flightIata);
      emit(FlightLookupSuccess(result));
    } catch (e) {
      emit(FlightLookupFailure(e.toString()));
    }
  }

  Future<void> _onAddRequested(
      FlightAddRequested event, Emitter<FlightState> emit) async {
    try {
      await _repository.addFlight(event.flight);
      // Reload flights after adding
      add(FlightLoadRequested());
    } catch (e) {
      emit(FlightLoadFailure('Failed to add flight: $e'));
    }
  }

  Future<void> _onDeleteRequested(
      FlightDeleteRequested event, Emitter<FlightState> emit) async {
    try {
      await _repository.deleteFlight(event.flightId);
      add(FlightLoadRequested());
    } catch (e) {
      emit(FlightLoadFailure('Failed to delete flight: $e'));
    }
  }
}
