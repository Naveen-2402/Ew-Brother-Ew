import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/native_bridge.dart';
import 'data/app_database.dart';
import 'data/repositories.dart';
import 'ui/app.dart';
import 'ui/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bridge = NativeBridge();
  final database = AppDatabase(bridge);
  await database.open();
  final signal = DataSignal();
  final app = AppController(
    bridge: bridge,
    database: database,
    settingsRepo: SettingsRepository(database, bridge),
    signal: signal,
  );
  await app.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: app),
        ChangeNotifierProvider<DataSignal>.value(value: signal),
        Provider<NativeBridge>.value(value: bridge),
        Provider<AppDatabase>.value(value: database),
        Provider<ReelsRepository>(create: (_) => ReelsRepository(database)),
        Provider<TasksRepository>(create: (_) => TasksRepository(database, bridge, signal)),
        Provider<HabitsRepository>(create: (_) => HabitsRepository(database, bridge, signal)),
        Provider<UsageRepository>(create: (_) => UsageRepository(database, bridge)),
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
