import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../blocs/flight/flight_bloc.dart';
import '../../models/models.dart';
import '../../services/airport_directory.dart';
import '../destination/radio_picker_sheet.dart';

/// Saves a flight the same way from every entry point:
///
/// 1. If the lookup came back without a timetable (ADS-B routes carry none),
///    ask for the real departure and arrival times first. Previously the
///    placeholder "now" was saved as the schedule.
/// 2. Save, and only report success once the write has succeeded.
/// 3. Offer to pick a local radio station at the destination.
///
/// Returns the saved flight, or null if the user cancelled or saving failed.
Future<Flight?> completeAddFlight(BuildContext context, Flight flight) async {
  final messenger = ScaffoldMessenger.of(context);
  final cs = Theme.of(context).colorScheme;
  final bloc = context.read<FlightBloc>();

  var toSave = flight;
  if (!flight.scheduleIsKnown) {
    final withTimes = await _askForSchedule(context, flight);
    if (withTimes == null) return null;
    toSave = withTimes;
  }

  final Flight saved;
  try {
    saved = await bloc.addFlight(toSave);
  } catch (_) {
    messenger.showSnackBar(SnackBar(
      content: Text("Couldn't track ${flight.flightNumber}. Please try again."),
      backgroundColor: cs.error,
    ));
    return null;
  }

  messenger.showSnackBar(SnackBar(
    content: Text('${saved.flightNumber} added to your tracked flights'),
    backgroundColor: cs.primary,
    duration: const Duration(seconds: 2),
  ));

  if (!context.mounted) return saved;
  final destination = await AirportDirectory.instance.lookup(saved.arrivalAirportIata);
  if (destination == null || !context.mounted) return saved;

  final wantsRadio = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.radio),
      title: Text('Tune in to ${destination.displayCity}?'),
      content: Text(
        'Pick a local radio station to hear news and music from ${destination.displayCity} before you land. '
        'You can change it any time from the flight.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Choose a station')),
      ],
    ),
  );
  if (wantsRadio != true || !context.mounted) return saved;

  final station = await showRadioPicker(context, destination: destination);
  if (station == null) return saved;
  try {
    await bloc.updateFlight(saved.copyWith(destinationRadio: station.toJson()));
    messenger.showSnackBar(SnackBar(content: Text('${station.name} saved for this trip')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't save the station.")));
  }
  return saved;
}

Future<Flight?> _askForSchedule(BuildContext context, Flight flight) {
  final now = DateTime.now();
  DateTime departure = DateTime(now.year, now.month, now.day, now.hour + 3);
  DateTime? arrival;

  return showDialog<Flight>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        Future<DateTime?> pick(DateTime initial) async {
          final date = await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: now.subtract(const Duration(days: 2)),
            lastDate: now.add(const Duration(days: 365)),
          );
          if (date == null || !context.mounted) return null;
          final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
          if (time == null) return null;
          return DateTime(date.year, date.month, date.day, time.hour, time.minute);
        }

        final fmt = DateFormat('EEE d MMM, HH:mm');
        final valid = arrival != null && arrival!.isAfter(departure);

        return AlertDialog(
          title: Text('When does ${flight.flightNumber} fly?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'We confirmed the route ${flight.routeDisplay}, but public flight data does not include '
                'timetables. Enter the times from your booking (local times).',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flight_takeoff),
                title: const Text('Departure'),
                subtitle: Text(fmt.format(departure)),
                onTap: () async {
                  final v = await pick(departure);
                  if (v != null) setState(() => departure = v);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flight_land),
                title: const Text('Arrival'),
                subtitle: Text(arrival == null ? 'Tap to set' : fmt.format(arrival!)),
                onTap: () async {
                  final v = await pick(arrival ?? departure.add(const Duration(hours: 2)));
                  if (v != null) setState(() => arrival = v);
                },
              ),
              if (arrival != null && !valid)
                Text('Arrival must be after departure.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(
                        context,
                        flight.copyWith(
                          scheduledDeparture: departure,
                          scheduledArrival: arrival,
                          scheduleIsKnown: true,
                          status: FlightStatusEnum.scheduled,
                        ),
                      )
                  : null,
              child: const Text('Track flight'),
            ),
          ],
        );
      },
    ),
  );
}
