import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/log_service.dart';

class LogsTab extends StatelessWidget {
  final LogService logService;

  const LogsTab({super.key, required this.logService});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ListenableBuilder(
      listenable: logService,
      builder: (context, _) {
        final logs = logService.entries.map((e) => '[${e.formattedTime}] ${e.message}').toList();
        
        return Scaffold(
          appBar: AppBar(
            title: const Text('Sistemske Napake & Logi'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              if (logs.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  onPressed: () => logService.clear(),
                ),
            ],
          ),
          body: logs.isEmpty
              ? Center(
                  child: Text(
                    'Ni zabeleženih sistemskih napak.',
                    style: TextStyle(
                      color: isDark ? AppTheme.textMuted : AppTheme.darkTextMuted,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkSurface : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        logs[index],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: isDark ? AppTheme.textMuted : AppTheme.darkTextMuted,
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
