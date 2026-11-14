import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:locreminder/services/offline_packs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'tile work is bounded across providers and cancelled work skips native I/O',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final replies = <Completer<List<Object?>>>[];
      final twoStarted = Completer<void>();
      messenger.setMockMethodCallHandler(OfflinePacks.channel, (_) {
        final reply = Completer<List<Object?>>();
        replies.add(reply);
        if (replies.length == 2) twoStarted.complete();
        return reply.future;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(OfflinePacks.channel, null),
      );
      final old = NativePackProvider('old');
      final current = NativePackProvider('current');
      final cancelled = vt.CancellationToken();
      final first = old.load(const vt.TileKey(4, 1, 1));
      final second = current.load(const vt.TileKey(4, 1, 2));
      final third = current.load(
        const vt.TileKey(4, 1, 3),
        cancellation: cancelled,
      );
      await twoStarted.future;
      expect(replies, hasLength(2));
      cancelled.cancel();
      replies[0].complete([]);
      expect(await first, isA<vt.TileResponseNotFound>());
      expect(await third, isA<vt.TileResponseCancelled>());
      expect(replies, hasLength(2));
      replies[1].complete([]);
      expect(await second, isA<vt.TileResponseNotFound>());
      final next = current.load(const vt.TileKey(4, 1, 4));
      await Future<void>.delayed(Duration.zero);
      expect(replies, hasLength(3));
      replies.last.complete([]);
      expect(await next, isA<vt.TileResponseNotFound>());
    },
  );
}
