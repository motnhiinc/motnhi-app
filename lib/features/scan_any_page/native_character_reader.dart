import 'package:flutter/services.dart';

abstract interface class CharacterReader {
  Future<void> open(String audioFilePath);
}

final class CharacterReaderCancelled implements Exception {}

final class CharacterReaderFailure implements Exception {
  const CharacterReaderFailure(this.code);

  final String code;
}

final class NativeCharacterReader implements CharacterReader {
  NativeCharacterReader({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('storybook_ar/character_reader');

  final MethodChannel _channel;

  @override
  Future<void> open(String audioFilePath) async {
    try {
      await _channel.invokeMethod<String>(
        'openCharacterReader',
        {'audioFilePath': audioFilePath},
      );
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') throw CharacterReaderCancelled();
      throw CharacterReaderFailure(error.code);
    }
  }
}
