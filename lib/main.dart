import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/native_bridge.dart';
import 'data/app_database.dart';
import 'data/games_repository.dart';
import 'data/repositories.dart';
import 'ui/app.dart';
import 'ui/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bridge = NativeBridge();
  final database = AppDatabase(bridge);
  final signal = DataSignal();
  final app = AppController(
    bridge: bridge,
    database: database,
    settingsRepo: SettingsRepository(database, bridge),
    signal: signal,
  );
  try {
    await database.open();
    await app.init();
  } catch (e) {
    // Without the database nothing works; say so instead of hanging on a blank screen.
    runApp(_StartupError(message: '$e'));
    return;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: app),
        ChangeNotifierProvider<DataSignal>.value(value: signal),
        Provider<NativeBridge>.value(value: bridge),
        Provider<AppDatabase>.value(value: database),
        Provider<ReelsRepository>(create: (_) => ReelsRepository(database)),
        Provider<TasksRepository>(create: (_) => TasksRepository(database, bridge, signal, () => app.dayStart)),
        Provider<HabitsRepository>(create: (_) => HabitsRepository(database, bridge, signal)),
        Provider<UsageRepository>(create: (_) => UsageRepository(database, bridge)),
        Provider<GamesRepository>(create: (_) => GamesRepository(database)),
        Provider<HistoryRepository>(
          create: (c) => HistoryRepository(
            database,
            c.read<ReelsRepository>(),
            c.read<UsageRepository>(),
            c.read<HabitsRepository>(),
          ),
        ),
      ],
      child: const EwApp(),
    ),
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1C1524),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Ew Brother Ew couldn't open its data.",
                  style: TextStyle(color: Color(0xFFF2ECE3), fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Close the app from Recents and open it again. If this keeps happening, '
                  'restart the phone. Reel counting may still be running in the background.',
                  style: TextStyle(color: Color(0xFFA99DB5), fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 16),
                Text(message, style: const TextStyle(color: Color(0xFF6E6379), fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
