import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

import '../services/offline_packs.dart';

class OfflinePackLayer extends StatefulWidget {
  const OfflinePackLayer({super.key, required this.fallback});
  final Widget fallback;
  @override
  State<OfflinePackLayer> createState() => _OfflinePackLayerState();
}

class _OfflinePackLayerState extends State<OfflinePackLayer> {
  final packs = OfflinePacks.instance;
  Timer? timer;
  vt.Theme? theme;
  vt.Theme? nightTheme;
  String? _revision;
  vt.TileProviders? _providers;
  @override
  void initState() {
    super.initState();
    packs.refresh();
    timer = Timer.periodic(const Duration(seconds: 20), (_) => packs.refresh());
    Future.wait([
      rootBundle.loadString('assets/maps/shortbread.json'),
      rootBundle.loadString('assets/maps/shortbread-night.json'),
    ]).then((raw) {
      if (mounted) {
        setState(() {
          theme = const vt.ThemeReader().read(
            jsonDecode(raw[0]) as Map<String, Object?>,
          );
          nightTheme = const vt.ThemeReader().read(
            jsonDecode(raw[1]) as Map<String, Object?>,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final center = camera.center;
    final bounds = camera.visibleBounds;
    return ListenableBuilder(
      listenable: packs,
      builder: (context, _) {
        final full = packs.packs.length == 21 && packs.ready == 21;
        final viewport = [
          center,
          bounds.northWest,
          bounds.northEast,
          bounds.southEast,
          bounds.southWest,
        ];
        final covered = full
            ? packs.covers(center.latitude, center.longitude)
            : viewport.every((p) => packs.covers(p.latitude, p.longitude));
        if (theme == null || !covered) {
          return widget.fallback;
        }
        final ready =
            packs.packs
                .where((p) => p['state'] == 'ready')
                .map((p) => '${p['id']}:${p['total']}')
                .toList()
              ..sort();
        final revision = ready.join(',');
        if (_revision != revision || _providers == null) {
          _revision = revision;
          _providers = vt.TileProviders({
            'shortbread': NativePackProvider(revision),
          });
        }
        return vt.VectorTileLayer(
          key: ValueKey(revision),
          theme: Theme.of(context).brightness == Brightness.dark
              ? nightTheme!
              : theme!,
          tileProviders: _providers!,
          concurrency: 2,
        );
      },
    );
  }
}
