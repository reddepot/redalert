import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'map_coverage.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

import 'mvt_merge.dart';

class OfflinePacks extends ChangeNotifier {
  static final instance = OfflinePacks();
  static const channel = MethodChannel('com.zaifears.locreminder/maps');
  List<Map<Object?, Object?>> packs = [];
  bool enabled = true;
  String? error;
  int freeBytes = 0, requiredBytes = 0;
  Future<void>? _pending;
  int get ready => packs.where((p) => p['state'] == 'ready').length;
  int get bytes =>
      packs.fold(0, (n, p) => n + ((p['bytes'] as num?)?.toInt() ?? 0));
  Map<String, dynamic>? _coverage;
  bool covers(double latitude, double longitude) => packs.any((p) {
    final rings = _coverage?[p['id']] as List?;
    return p['state'] == 'ready' &&
        rings != null &&
        MapCoverage.contains(rings, latitude, longitude);
  });
  String get label => '$ready/${packs.length} régions prêtes';
  Future<void> refresh({String method = 'status', bool? value}) {
    if (method == 'status' && _pending != null) return _pending!;
    final work = (_pending ?? Future<void>.value()).then(
      (_) => _refresh(method, value),
    );
    _pending = work;
    return work.whenComplete(() {
      if (identical(_pending, work)) _pending = null;
    });
  }

  Future<void> _refresh(String method, bool? value) async {
    try {
      _coverage ??= jsonDecode(
        await rootBundle.loadString('assets/maps/coverage.json'),
      ) as Map<String, dynamic>;
      final data = await channel.invokeMapMethod<Object?, Object?>(method, {
        'enabled': value,
      });
      if (data != null) {
        enabled = data['enabled'] == true;
        packs = (data['packs'] as List)
            .map((p) => Map<Object?, Object?>.from(p as Map))
            .toList();
        freeBytes = (data['freeBytes'] as num).toInt();
        requiredBytes = (data['requiredBytes'] as num).toInt();
      }
      error = null;
    } on MissingPluginException {
      error = 'Téléchargement disponible sur Android.';
    } catch (_) {
      error = 'Téléchargement indisponible. Vérifier le stockage et réessayer.';
    } finally {
      notifyListeners();
    }
  }
}

/// SQLite reads happen on Android's worker; regional seams merge off the UI isolate.
class NativePackProvider extends vt.VectorTileProvider {
  NativePackProvider(this.revision);
  final String revision;
  static final _slots = _TileSlots(2);
  @override
  int get minimumZoom => 0;
  @override
  int get maximumZoom => 14;
  @override
  String get cacheKey => 'shortbread:$revision';
  @override
  bool get cacheBytesToDisk => false;
  @override
  Future<vt.TileResponse> load(
    vt.TileKey tile, {
    vt.CancellationToken? cancellation,
  }) async {
    if (cancellation?.isCancelled == true) {
      return const vt.TileResponseCancelled();
    }
    await _slots.acquire();
    try {
      if (cancellation?.isCancelled == true) {
        return const vt.TileResponseCancelled();
      }
      final response = await OfflinePacks.channel.invokeListMethod<Object?>(
        'tile',
        {'z': tile.z, 'x': tile.x, 'y': tile.y},
      );
      final data = response?.whereType<Uint8List>().toList() ?? [];
      if (cancellation?.isCancelled == true) {
        return const vt.TileResponseCancelled();
      }
      if (data.isEmpty) return const vt.TileResponseNotFound();
      // Decode/bound even one archive off the UI isolate before the renderer.
      final merged = await compute(mergeRegionalTiles, data);
      if (cancellation?.isCancelled == true) {
        return const vt.TileResponseCancelled();
      }
      return vt.TileResponseData(merged);
    } catch (e) {
      return vt.TileResponseError(e);
    } finally {
      _slots.release();
    }
  }
}

/// Bound native buffers and decode isolates together, including across revisions.
class _TileSlots {
  _TileSlots(this.maximum);
  final int maximum;
  var active = 0;
  final waiting = Queue<Completer<void>>();
  Future<void> acquire() {
    if (active < maximum) {
      active++;
      return Future<void>.value();
    }
    final turn = Completer<void>();
    waiting.add(turn);
    return turn.future;
  }

  void release() {
    if (waiting.isEmpty) {
      active--;
    } else {
      waiting.removeFirst().complete();
    }
  }
}
