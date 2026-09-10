import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'config/theme.dart';
import 'config/routes.dart';
import 'blocs/auth/auth_bloc.dart';
import 'blocs/flight/flight_bloc.dart';
import 'blocs/trip/trip_bloc.dart';
import 'blocs/sharing/sharing_bloc.dart';
import 'blocs/quota/quota_bloc.dart';
import 'providers/supabase_flight_provider.dart';
import 'repositories/flight_repository.dart';
import 'repositories/trip_repository.dart';
import 'repositories/sharing_repository.dart';
import 'repositories/quota_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  // Initialize Firebase (Requires flutterfire configure)
  // await Firebase.initializeApp(
  //   options: DefaultFirebaseOptions.currentPlatform,
  // );

  // Initialize Supabase
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  runApp(const SkyPulseApp());
}

class SkyPulseApp extends StatelessWidget {
  const SkyPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (_) => AuthBloc(
            supabase: Supabase.instance.client,
          )..add(AuthCheckRequested()),
        ),
        BlocProvider<FlightBloc>(
          create: (_) => FlightBloc(
            repository: FlightRepository(
              supabase: Supabase.instance.client,
              provider: SupabaseFlightProvider(Supabase.instance.client),
            ),
          )..add(FlightLoadRequested()),
        ),
        BlocProvider<TripBloc>(
          create: (_) => TripBloc(
            repository: TripRepository(
              supabase: Supabase.instance.client,
            ),
          )..add(TripLoadRequested()),
        ),
        BlocProvider<SharingBloc>(
          create: (_) => SharingBloc(
            repository: SharingRepository(
              supabase: Supabase.instance.client,
            ),
          ),
        ),
        BlocProvider<QuotaBloc>(
          create: (_) => QuotaBloc(
            repository: QuotaRepository(
              provider: SupabaseFlightProvider(Supabase.instance.client),
            ),
          )..add(QuotaLoadRequested()),
        ),
      ],
      child: BlocBuilder<AuthBloc, AuthBlocState>(
        builder: (context, authState) {
          final isAuthenticated = authState is AuthAuthenticated;

          final router = AppRouter.router(isAuthenticated: isAuthenticated);

          return MaterialApp.router(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: SkyPulseTheme.lightTheme,
            darkTheme: SkyPulseTheme.darkTheme,
            themeMode: ThemeMode.dark, // Default to dark (Stitch design)
            routerConfig: router,
          );
        },
      ),
    );
  }
}
