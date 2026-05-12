import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService._internal() {
    _init();
  }

  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOffline = false;

  bool get isOffline => _isOffline;
  Stream<bool> get onStatusChanged => _controller.stream;

  void _init() {
    _subscription ??=
        _connectivity.onConnectivityChanged.listen((results) {
      _setOffline(_resultsAreOffline(results));
    });
    refresh();
  }

  Future<void> refresh() async {
    final results = await _connectivity.checkConnectivity();
    _setOffline(_resultsAreOffline(results));
  }

  Future<bool> hasInternet() async {
    await refresh();
    return !_isOffline;
  }

  bool _resultsAreOffline(List<ConnectivityResult> results) {
    return results.isEmpty ||
        results.every((result) => result == ConnectivityResult.none);
  }

  void _setOffline(bool value) {
    if (_isOffline == value) {
      return;
    }
    _isOffline = value;
    _controller.add(value);
  }
}
