import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/app_controller.dart';
import '../theme/app_theme.dart';

class ScanScheduleDialog extends StatefulWidget {
  const ScanScheduleDialog({super.key, required this.controller});
  final AppController controller;

  @override
  State<ScanScheduleDialog> createState() => _ScanScheduleDialogState();
}

class _ScanScheduleDialogState extends State<ScanScheduleDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.refreshDiagnostics();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final diag = controller.workerDiagnostics;
    
    final lastAutoScan = diag['startedAt'] != null 
        ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(diag['startedAt'])) 
        : 'Never';
    final lastFinishedAt = diag['finishedAt'] != null 
        ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(diag['finishedAt'])) 
        : 'Never';
    final workerSuccess = diag['succeeded'] ?? false;
    final workerError = diag['error'] ?? 'None';
    final totalToday = diag['totalToday'] ?? 0;
    final filtersScanned = diag['filtersScanned'] ?? 0;
    final adsParsed = diag['adsParsed'] ?? 0;
    final newAdsFound = diag['newAdsFound'] ?? 0;
    final notificationsSent = diag['notificationsSent'] ?? 0;
    final lastNotificationAt = diag['lastNotificationAt'] != null 
        ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(diag['lastNotificationAt'])) 
        : 'Never';
    final detailLog = diag['detailLog'] ?? 'No detailed logs available.';

    // Derived last successful scan (from diagnostics)
    String lastSuccessfulAuto = 'Never';
    if (workerSuccess && diag['finishedAt'] != null) {
      lastSuccessfulAuto = DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(diag['finishedAt']));
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('SCAN DIAGNOSTICS', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: () => controller.refreshDiagnostics()),
                  ],
                ),
                const Divider(),
                
                _infoRow(context, 'Current Time', DateFormat('HH:mm:ss').format(now)),
                _infoRow(context, 'Last Auto Scan (Start)', lastAutoScan, color: AppTheme.brandPurple),
                _infoRow(context, 'Last Successful Auto', lastSuccessfulAuto, color: Colors.green),
                _infoRow(context, 'Last Worker Finish', lastFinishedAt),
                _infoRow(context, 'Worker Succeeded', workerSuccess ? 'YES' : 'NO', color: workerSuccess ? Colors.green : Colors.red),
                _infoRow(context, 'Last Worker Error', workerError, color: workerError != 'None' && workerError != 'Night pause' ? Colors.red : null),
                _infoRow(context, 'Total Auto Scans Today', '$totalToday'),
                
                const Divider(),
                const Text('RUNTIME DATA (Last Run)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                _infoRow(context, 'Filters Scanned', '$filtersScanned'),
                _infoRow(context, 'Ads Parsed', '$adsParsed'),
                _infoRow(context, 'New Ads Found', '$newAdsFound', color: newAdsFound > 0 ? Colors.green : null),
                _infoRow(context, 'Notifications Sent', '$notificationsSent', color: notificationsSent > 0 ? Colors.green : null),
                _infoRow(context, 'Last Notification', lastNotificationAt),
                
                const SizedBox(height: 16),
                const Text('DETAILED WORKER LOG (Last Run):', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    detailLog,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: Colors.blueGrey),
                  ),
                ),

                const SizedBox(height: 16),
                const Text('SCHEDULER STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                _infoRow(context, 'Next Planned Scan', controller.nextScanTime != null ? DateFormat('HH:mm').format(controller.nextScanTime!) : '--:--'),
                _infoRow(context, 'Worker Status', 'ENQUEUED (WorkManager)', color: Colors.green),

                const SizedBox(height: 24),
                const Text('XIAOMI / MIUI NOTICE:', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange)),
                const Text('Enable "Auto-start" and set "Battery saver" to "No restrictions" for reliable background scans.', 
                  style: TextStyle(fontSize: 9, color: Colors.grey)),

                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: controller.isScanning ? null : () async {
                    await controller.runWorkerNow();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Test Worker triggered... Refresh in 5s.')));
                    }
                  },
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('RUN BACKGROUND SCAN NOW'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                ),
                
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: controller.isScanning ? null : () {
                    Navigator.pop(context);
                    controller.runSequentialScan();
                  },
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('RUN MANUAL SCAN'),
                ),
                
                const SizedBox(height: 16),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}
