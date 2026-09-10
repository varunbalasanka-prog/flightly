import '../../models/models.dart';
import '../../providers/flight_data_provider.dart';

class QuotaRepository {
  final FlightDataProvider _provider;

  QuotaRepository({required this._provider});

  Future<UsageQuota> getQuota() async {
    return _provider.getQuotaStatus();
  }
}
