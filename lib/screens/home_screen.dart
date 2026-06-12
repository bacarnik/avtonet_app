import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../widgets/hidden_webview.dart';
import 'history_tab.dart';
import 'tracker_tab.dart';

/// REFACTORED: Compact Dual-Tab Navigation Architecture
/// Hosts the Tracker (Dashboard) and History screens.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              TrackerTab(controller: c),
              HistoryTab(controller: c),
            ],
          ),
          HiddenWebView(scraper: c.scraper),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.sensors),
            activeIcon: Icon(Icons.sensors),
            label: 'Tracker',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            activeIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
