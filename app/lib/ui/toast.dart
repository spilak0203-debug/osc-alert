import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// Short message at the bottom of the screen: Android's own toast on phones, a look-alike on
/// Windows.
class Toaster {
  static final GlobalKey<NavigatorState> navigator = GlobalKey();
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(String message, {bool long = false}) {
    if (Platform.isAndroid) {
      Fluttertoast.showToast(msg: message, toastLength: long ? Toast.LENGTH_LONG : Toast.LENGTH_SHORT);
      return;
    }
    final overlay = navigator.currentState?.overlay;
    if (overlay == null) return;
    _timer?.cancel();
    _entry?.remove();
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        right: 0,
        bottom: 96,
        child: IgnorePointer(
          child: Center(
            child: Material(
              color: const Color(0xE6303030),
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(Duration(milliseconds: long ? 3500 : 2000), () {
      entry.remove();
      if (_entry == entry) _entry = null;
    });
  }
}
