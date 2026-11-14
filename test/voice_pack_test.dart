import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/poi_type.dart';

void main() {
  test('all supported points and distance bins have complete embedded phrases',
      () {
    final manifest =
        jsonDecode(File('assets/voice/fr/manifest.json').readAsStringSync())
            as Map;
    final clips = manifest['utterances'] as Map;
    for (final type in PoiType.values) {
      for (final suffix in [
        'near',
        30,
        50,
        75,
        100,
        150,
        200,
        250,
        300,
        400,
        500,
        600,
        750,
        1000,
        1250,
        1500,
        2000,
        2500,
        3000
      ]) {
        final key = '${type.name}_$suffix';
        expect(clips.containsKey(key), isTrue, reason: key);
        final file = File('assets/voice/fr/$key.ogg');
        expect(file.lengthSync(), greaterThan(1000));
        expect(file.readAsBytesSync().take(4).toList(),
            [79, 103, 103, 83]); // OggS
        expect((clips[key] as Map)['seconds'], inInclusiveRange(.5, 5.5));
      }
    }
    expect(clips.containsKey('speed_warning'), isTrue);
    expect(
        clips.values
            .every((v) => !(v['text'] as String).contains('Limitation')),
        isTrue);
  });
}
