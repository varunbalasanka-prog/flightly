import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../blocs/flight/flight_bloc.dart';
import '../../models/models.dart';

/// Manual flight entry — no API call consumed.
class ManualFlightScreen extends StatefulWidget {
  const ManualFlightScreen({super.key});

  @override
  State<ManualFlightScreen> createState() => _ManualFlightScreenState();
}

class _ManualFlightScreenState extends State<ManualFlightScreen> {
  final _formKey = GlobalKey<FormState>();
  final _flightNumberCtrl = TextEditingController();
  final _depAirportCtrl = TextEditingController();
  final _arrAirportCtrl = TextEditingController();
  DateTime _departureDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _departureTime = const TimeOfDay(hour: 10, minute: 0);
  DateTime _arrivalDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _arrivalTime = const TimeOfDay(hour: 14, minute: 0);

  @override
  void dispose() {
    _flightNumberCtrl.dispose();
    _depAirportCtrl.dispose();
    _arrAirportCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Flight Manually')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // No API call notice
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Manual entries don\'t use API quota',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            TextFormField(
              controller: _flightNumberCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Flight Number',
                hintText: 'e.g. AA472',
                prefixIcon: Icon(Icons.flight),
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _depAirportCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'From (IATA)',
                      hintText: 'DFW',
                      prefixIcon: Icon(Icons.flight_takeoff),
                    ),
                    validator: (v) =>
                        v == null || v.length != 3 ? '3-letter code' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _arrAirportCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'To (IATA)',
                      hintText: 'JFK',
                      prefixIcon: Icon(Icons.flight_land),
                    ),
                    validator: (v) =>
                        v == null || v.length != 3 ? '3-letter code' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text('Departure',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(true),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_formatDate(_departureDate)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(true),
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(_departureTime.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text('Arrival',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_formatDate(_arrivalDate)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(false),
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(_arrivalTime.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Text('Add to Trip'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  Future<void> _pickDate(bool isDeparture) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isDeparture ? _departureDate : _arrivalDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isDeparture) {
          _departureDate = picked;
        } else {
          _arrivalDate = picked;
        }
      });
    }
  }

  Future<void> _pickTime(bool isDeparture) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isDeparture ? _departureTime : _arrivalTime,
    );
    if (picked != null) {
      setState(() {
        if (isDeparture) {
          _departureTime = picked;
        } else {
          _arrivalTime = picked;
        }
      });
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final depDateTime = DateTime(
        _departureDate.year,
        _departureDate.month,
        _departureDate.day,
        _departureTime.hour,
        _departureTime.minute,
      );

      final arrDateTime = DateTime(
        _arrivalDate.year,
        _arrivalDate.month,
        _arrivalDate.day,
        _arrivalTime.hour,
        _arrivalTime.minute,
      );

      final flightNumber = _flightNumberCtrl.text.trim().toUpperCase();
      final depIata = _depAirportCtrl.text.trim().toUpperCase();
      final arrIata = _arrAirportCtrl.text.trim().toUpperCase();

      final flight = Flight(
        id: '',
        flightNumber: flightNumber,
        airlineIata: flightNumber.length >= 2 ? flightNumber.substring(0, 2) : 'FL',
        departureAirportIata: depIata,
        arrivalAirportIata: arrIata,
        scheduledDeparture: depDateTime,
        scheduledArrival: arrDateTime,
        isManualEntry: true,
        status: FlightStatusEnum.scheduled,
        lastUpdated: DateTime.now(),
      );

      context.read<FlightBloc>().add(FlightAddRequested(flight));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$flightNumber saved to your tracked flights!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );

      Navigator.of(context).pop();
    }
  }
}
