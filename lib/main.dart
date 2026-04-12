import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

export 'app/app.dart' show MyApp;

void main() {
  runApp(const ProviderScope(child: MyApp()));
}
