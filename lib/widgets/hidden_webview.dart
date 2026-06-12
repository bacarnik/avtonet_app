import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/avtonet_scraper_service.dart';

/// Skrit WebView (1×1) – ne prekriva uporabniškega vmesnika.
class HiddenWebView extends StatelessWidget {
  const HiddenWebView({super.key, required this.scraper});

  final AvtonetScraperService scraper;

  @override
  Widget build(BuildContext context) {
    if (!scraper.isReady) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      top: 0,
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0.01,
        child: IgnorePointer(
          child: WebViewWidget(controller: scraper.controller),
        ),
      ),
    );
  }
}
