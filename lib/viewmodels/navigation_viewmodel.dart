import 'package:flutter_riverpod/flutter_riverpod.dart';

// 1. Define the Notifier
class NavigationNotifier extends Notifier<int> {
  @override
  int build() {
    return 0; // Initial state (Players tab)
  }

  void setTab(int index) {
    state = index;
  }
}

// 2. Define the Provider
final navigationProvider = NotifierProvider<NavigationNotifier, int>(() {
  return NavigationNotifier();
});
