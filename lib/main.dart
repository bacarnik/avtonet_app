import 'package:flutter/material.dart';

import 'background/workmanager_entrypoint.dart';
import 'controllers/app_controller.dart';
import 'screens/home_screen.dart';
import 'services/avtonet_catalog_service.dart';
import 'services/avtonet_scraper_service.dart';
import 'services/catchup_service.dart';
import 'services/lifecycle_scheduler.dart';
import 'services/log_service.dart';
import 'services/notification_service.dart';
import 'services/scan_orchestrator.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'utils/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final log = LogService();
  AppLogger.init(log);
  
  final storage = StorageService();
  final notifications = NotificationService.instance;
  await notifications.initialize(requestPermission: true);

  final catalog = AvtonetCatalogService();
  final scraper = AvtonetScraperService(log);
  
  final engine = ScanEngine(
    storage: storage,
    log: log,
    scraper: scraper,
    notifications: notifications,
  );

  final catchUp = CatchUpService(
    storage: storage,
    orchestrator: engine,
  );

  final lifecycleScheduler = LifecycleScheduler();

  final controller = AppController(
    storage: storage,
    log: log,
    scraper: scraper,
    catalog: catalog,
    orchestrator: engine,
    catchUp: catchUp,
    lifecycleScheduler: lifecycleScheduler,
  );

  try {
    await registerBackgroundTasks();
  } catch (e) {
    AppLogger.error('[BACKGROUND]', 'Workmanager registration failed', e);
  }

  runApp(AvtonetApp(controller: controller));
}

class AvtonetApp extends StatefulWidget {
  const AvtonetApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<AvtonetApp> createState() => _AvtonetAppState();
}

class _AvtonetAppState extends State<AvtonetApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'avtonetFinder',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          if (!widget.controller.initialized) {
            return const _LoadingSplash();
          }
          return HomeScreen(controller: widget.controller);
        },
      ),
    );
  }
}

class _LoadingSplash extends StatelessWidget {
  const _LoadingSplash();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.brandPurple),
              const SizedBox(height: 24),
              Text(
                'avtonetFinder',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'STABILIZING SYSTEMS',
                style: TextStyle(
                  color: AppTheme.brandPurple,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
