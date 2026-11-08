import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Vietnamese is the only app UI language, regardless of device language or
/// a previously saved override. Story content language remains independent.
final appLocaleProvider = Provider<Locale>((ref) => const Locale('vi'));
