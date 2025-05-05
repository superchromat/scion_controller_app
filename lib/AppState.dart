import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  void setConnectionState(bool value) {
    if (_isConnected != value) {
      _isConnected = value;
      notifyListeners(); // triggers rebuilds
    }
  }
}