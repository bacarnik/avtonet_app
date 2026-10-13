import 'package:flutter_test/flutter_test.dart';

import 'package:avtonet_app/main.dart';
import 'package:avtonet_app/controllers/app_controller.dart';
import 'package:avtonet_app/services/avtonet_catalog_service.dart';
import 'package:avtonet_app/services/avtonet_scraper_service.dart';
import 'package:avtonet_app/services/catchup_service.dart';
import 'package:avtonet_app/services/lifecycle_scheduler.dart';
import 'package:avtonet_app/services/log_service.dart';
import 'package:avtonet_app/services/notification_service.dart';
import 'package:avtonet_app/services/scan_orchestrator.dart';
import 'package:avtonet_app/services/storage_service.dart';

void main() {
  testWidgets('prikaže zaslon za nalaganje', (WidgetTester tester) async {
    final log = LogService();
    final storage = StorageService();
    final scraper = AvtonetScraperService(log);
    final catalog = AvtonetCatalogService(scraper);
    final engine = ScanEngine(
      storage: storage,
      log: log,
      scraper: scraper,
      notifications: NotificationService.instance,
    );
    final controller = AppController(
      storage: storage,
      log: log,
      scraper: scraper,
      catalog: catalog,
      orchestrator: engine,
      catchUp: CatchUpService(storage: storage, orchestrator: engine),
      lifecycleScheduler: LifecycleScheduler(),
    );

    await tester.pumpWidget(AvtonetApp(controller: controller));
    expect(find.text('AvtoNet Skener'), findsOneWidget);
  });
}
