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
    
    final startedAt = diag['startedAt'] != null 
        ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(diag['startedAt'])) 
        : 'Never';
    final finishedAt = diag['finishedAt'] != null 
        ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(diag['finishedAt'])) 
        : 'Never';
    
    final lastRegistration = diag['lastRegistration'] != null
        ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(diag['lastRegistration']))
        : 'Never';

    final lastSuccess = diag['lastSuccessAt'] != null
        ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(diag['lastSuccessAt']))
        : 'Never';
    
    final lastFailure = diag['lastFailureAt'] != null
        ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(diag['lastFailureAt']))
        : 'Never';

    final exitReason = diag['lastResult'] ?? 'UNKNOWN';
    final duration = diag['durationMs'] != null ? '${(diag['durationMs'] / 1000).toStringAsFixed(1)}s' : '--';
    
    final activeFilters = diag['activeFilters'] ?? 0;
    final successFilters = diag['successFilters'] ?? 0;
    final failedFilters = diag['failedFilters'] ?? 0;
    
    final usedHttp = diag['usedHttpClient'] ?? false;
    final usedWeb = diag['usedWebView'] ?? false;

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
                    Text('WORKER AUDIT', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: () => controller.refreshDiagnostics()),
                  ],
                ),
                const Divider(),
                
                _infoRow(context, 'Worker Registered', lastRegistration),
                _infoRow(context, 'Last Worker Start', startedAt, color: AppTheme.brandPurple),
                _infoRow(context, 'Last Worker Finish', finishedAt),
                _infoRow(context, 'Last Success At', lastSuccess, color: Colors.green),
                _infoRow(context, 'Last Failure At', lastFailure, color: Colors.red),
                
                const Divider(),
                const Text('LAST RUN DETAILS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                _infoRow(context, 'Exit Reason', exitReason, color: exitReason == 'SUCCESS' ? Colors.green : Colors.orange),
                _infoRow(context, 'Duration', duration),
                _infoRow(context, 'Filters (Act/Suc/Fail)', '$activeFilters / $successFilters / $failedFilters'),
                _infoRow(context, 'Methods Used', '${usedHttp ? "HTTP" : ""} ${usedWeb ? "WebView" : ""}'.trim()),
                
                const Divider(),
                const Text('SCHEDULER STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                _infoRow(context, 'Next Planned Scan', controller.nextScanTime != null ? DateFormat('HH:mm').format(controller.nextScanTime!) : '--:--'),
                _infoRow(context, 'Periodic Task', 'ACTIVE (15m)', color: Colors.green),

                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: controller.isScanning ? null : () async {
                    await controller.runWorkerNow();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Test Worker triggered...')));
                    }
                  },
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('TRIGGER TEST WORKER'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
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
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11))),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }
}
