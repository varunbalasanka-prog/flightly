import 'package:flutter_bloc/flutter_bloc.dart';

import '../../providers/flight_data_provider.dart';
import '../../repositories/flight_repository.dart';

/// Provider lookups (flight search), kept separate from [FlightBloc].
///
/// These used to share one state union with the user's tracked-flight list,
/// which meant a realtime list update would overwrite whatever search results
/// were on screen. Splitting them lets the list own a live subscription.

// --- Events ---
abstract class FlightLookupEvent {}

class FlightLookupRequested extends FlightLookupEvent {
  final String flightIata;
  FlightLookupRequested(this.flightIata);
}

class FlightLookupCleared extends FlightLookupEvent {}

// --- States ---
abstract class FlightLookupState {}

class FlightLookupInitial extends FlightLookupState {}

class FlightLookupInProgress extends FlightLookupState {}

class FlightLookupSuccess extends FlightLookupState {
  final FlightLookupResult result;
  FlightLookupSuccess(this.result);
}

class FlightLookupFailure extends FlightLookupState {
  final String error;
  FlightLookupFailure(this.error);
}

// --- BLoC ---
class FlightLookupBloc extends Bloc<FlightLookupEvent, FlightLookupState> {
  final FlightRepository _repository;

  FlightLookupBloc({required this._repository}) : super(FlightLookupInitial()) {
    on<FlightLookupRequested>(_onLookupRequested);
    on<FlightLookupCleared>((_, emit) => emit(FlightLookupInitial()));
  }

  Future<void> _onLookupRequested(
    FlightLookupRequested event,
    Emitter<FlightLookupState> emit,
  ) async {
    emit(FlightLookupInProgress());
    try {
      final result = await _repository.lookupFlight(event.flightIata);
      if (result.hasError && !result.hasResults) {
        emit(FlightLookupFailure(result.error!));
        return;
      }
      emit(FlightLookupSuccess(result));
    } catch (_) {
      emit(FlightLookupFailure(
        "Couldn't search for that flight. Please try again.",
      ));
    }
  }
}
