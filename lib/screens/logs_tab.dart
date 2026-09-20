import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/log_service.dart';
import '../models/scan_diagnostic.dart';
import '../services/storage_service.dart';

class LogsTab extends StatefulWidget {
  final LogService logService;

  const LogsTab({super.key, required this.logService});

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  List<ScanSession> _diagnostics = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    setState(() => _isLoading = true);
    final storage = StorageService();
    final data = await storage.loadScanDiagnostics();
    setState(() {
      _diagnostics = data;
      _isLoading = false;
    });
  }

  String _formatSession(ScanSession s) {
    final sb = StringBuffer();
    sb.writeln('==================================================');
    sb.writeln('SCAN SESSION');
    sb.writeln('===================');
    sb.writeln('Date: ${s.startTime.year}-${s.startTime.month.toString().padLeft(2, '0')}-${s.startTime.day.toString().padLeft(2, '0')}');
    sb.writeln('Start: ${s.startTime.hour.toString().padLeft(2, '0')}:${s.startTime.minute.toString().padLeft(2, '0')}:${s.startTime.second.toString().padLeft(2, '0')}');
    if (s.endTime != null) {
      sb.writeln('End: ${s.endTime!.hour.toString().padLeft(2, '0')}:${s.endTime!.minute.toString().padLeft(2, '0')}:${s.endTime!.second.toString().padLeft(2, '0')}');
    }
    sb.writeln('Duration: ${s.durationMs ?? 0}ms');
    sb.writeln('Mode: ${s.method}');
    sb.writeln('Result: ${s.exitReason ?? 'UNKNOWN'}');
    sb.writeln('');
    sb.writeln('Worker status: ${s.triggerReason ?? 'N/A'}');
    sb.writeln('Lock blocked: ${s.isLockBlocked}');
    if (s.isLockBlocked) sb.writeln('Lock owner: ${s.lockOwner}');
    sb.writeln('Active filters: ${s.activeFiltersCount}');
    sb.writeln('Total new ads: ${s.totalNewAds ?? 0}');
    sb.writeln('');

    for (var i = 0; i < s.filters.length; i++) {
      final f = s.filters[i];
      sb.writeln('---');
      sb.writeln('## FILTER ${i + 1}: ${f.filterName}');
      sb.writeln('Brand: ${f.brand}');
      sb.writeln('Model: ${f.model}');
      sb.writeln('Status: ${f.status}');
      if (f.reason != null) sb.writeln('Reason: ${f.reason}');
      sb.writeln('Ads: found=${f.adsFound}, new=${f.newAdsFound}, known=${f.knownAdsFound}');
      sb.writeln('Method: ${f.usedWebView ? 'WebView' : 'HttpClient'}${f.usedHttpClientFallback ? ' (Fallback)' : ''}');
      sb.writeln('Cloudflare: ${f.cloudflareDetected}');
      sb.writeln('URL: ${f.url}');
      sb.writeln('URL PARAMETERS:');
      f.urlParams.forEach((key, value) {
        sb.writeln('  $key=$value');
      });
      
      if (f.error != null) {
        sb.writeln('ERROR: ${f.error}');
        if (f.stackTrace != null) sb.writeln('STACK TRACE:\n${f.stackTrace}');
      }

      for (var p in f.pages) {
        sb.writeln('  > PAGE ${p.pageNumber}: found=${p.adsFound}, next=${p.hasNextPage}, method=${p.method}, status=${p.httpStatus}');
        if (p.error != null) sb.writeln('    ERROR: ${p.error}');
        if (p.webViewError != null) sb.writeln('    WebView Error: ${p.webViewError}');
      }
      sb.writeln('');
    }
    
    sb.writeln('==================================================');
    sb.writeln('END SCAN');
    sb.writeln('========');
    sb.writeln('');
    return sb.toString();
  }

  Future<void> _copyAllLogs() async {
    final sb = StringBuffer();
    sb.writeln('SCAN DIAGNOSTIC LOG');
    sb.writeln('Generated: ${DateTime.now().toIso8601String()}');
    sb.writeln('');
    for (var s in _diagnostics) {
      sb.write(_formatSession(s));
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('LOGS COPIED')));
    }
  }

  Future<void> _copySingleLog(ScanSession s) async {
    await Clipboard.setData(ClipboardData(text: _formatSession(s)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SESSION LOG COPIED')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Debug Console'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'SCAN DIAGNOSTICS'),
              Tab(text: 'SYSTEM ERRORS'),
            ],
            indicatorColor: AppTheme.brandPurple,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadDiagnostics,
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildDiagnosticsTab(isDark),
            _buildSystemErrorsTab(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsTab(bool isDark) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_diagnostics.isEmpty) {
      return const Center(child: Text('No scan diagnostics available.'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.copy_all),
              label: const Text('COPY ALL LOGS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: _copyAllLogs,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _diagnostics.length,
            itemBuilder: (context, index) {
              final s = _diagnostics[index];
              final isSuccess = s.exitReason == 'SUCCESS';
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: Icon(
                    isSuccess ? Icons.check_circle : Icons.error,
                    color: isSuccess ? Colors.green : Colors.red,
                  ),
                  title: Text('${s.startTime.day}.${s.startTime.month}. ${s.startTime.hour}:${s.startTime.minute.toString().padLeft(2, '0')} — ${s.method}'),
                  subtitle: Text('Result: ${s.exitReason} • Ads: ${s.totalNewAds ?? 0}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copySingleLog(s),
                  ),
                  onTap: () => _showSessionDetails(s),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showSessionDetails(ScanSession s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Session: ${s.method}'),
        content: SingleChildScrollView(
          child: SelectableText(_formatSession(s), style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
          TextButton(onPressed: () => _copySingleLog(s), child: const Text('COPY')),
        ],
      ),
    );
  }

  Widget _buildSystemErrorsTab(bool isDark) {
    return ListenableBuilder(
      listenable: widget.logService,
      builder: (context, _) {
        final logs = widget.logService.entries.map((e) => '[${e.formattedTime}] ${e.message}').toList();
        
        if (logs.isEmpty) {
          return Center(
            child: Text(
              'Ni zabeleženih sistemskih napak.',
              style: TextStyle(
                color: isDark ? AppTheme.textMuted : AppTheme.darkTextMuted,
              ),
            ),
          );
        }

        return ListView.builder(
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
        );
      },
    );
  }
}
