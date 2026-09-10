import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/models.dart';
import '../../repositories/quota_repository.dart';

// --- Events ---
abstract class QuotaEvent {}

class QuotaLoadRequested extends QuotaEvent {}

// --- States ---
abstract class QuotaState {}

class QuotaInitial extends QuotaState {}
class QuotaLoadInProgress extends QuotaState {}
class QuotaLoadSuccess extends QuotaState {
  final UsageQuota quota;
  QuotaLoadSuccess(this.quota);
}
class QuotaLoadFailure extends QuotaState {
  final String error;
  QuotaLoadFailure(this.error);
}

// --- BLoC ---
class QuotaBloc extends Bloc<QuotaEvent, QuotaState> {
  final QuotaRepository _repository;

  QuotaBloc({required this._repository})
      : super(QuotaInitial()) {
    on<QuotaLoadRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
      QuotaLoadRequested event, Emitter<QuotaState> emit) async {
    emit(QuotaLoadInProgress());
    try {
      final quota = await _repository.getQuota();
      emit(QuotaLoadSuccess(quota));
    } catch (e) {
      emit(QuotaLoadFailure(e.toString()));
    }
  }
}
