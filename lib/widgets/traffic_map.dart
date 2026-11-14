import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/traffic_data.dart';
import 'map_control.dart';
import 'map_scale.dart';
import 'map_tiles.dart';

class _TrafficEndpoint {
  const _TrafficEndpoint(this.record, this.point, this.role);
  final TrafficRecord record;
  final LatLng point;
  final String role;
}

/// Consultation geometry only. Segment endpoints are never joined by a false road.
class TrafficMap extends StatefulWidget {
  const TrafficMap({
    super.key,
    required this.records,
    required this.onRecord,
    this.tileLayer,
    this.style = MapStyle.standard,
  });
  final List<TrafficRecord> records;
  final ValueChanged<TrafficRecord> onRecord;
  final Widget? tileLayer;
  final MapStyle style;
  @override
  State<TrafficMap> createState() => _TrafficMapState();
}

class _TrafficMapState extends State<TrafficMap> {
  final _controller = MapController();
  bool _ready = false;
  void _zoom(double by) {
    final c = _controller.camera;
    _controller.move(c.center, (c.zoom + by).clamp(mapMinZoom, mapMaxZoom));
  }

  List<Marker> _markers() {
    final camera = _controller.camera;
    final buckets = <(int, int), List<_TrafficEndpoint>>{};
    void add(TrafficRecord record, LatLng? point, String role) {
      if (point == null || !camera.visibleBounds.contains(point)) return;
      final pixel = camera.projectAtZoom(point);
      final key = ((pixel.dx / 56).floor(), (pixel.dy / 56).floor());
      (buckets[key] ??= []).add(_TrafficEndpoint(record, point, role));
    }

    for (final r in widget.records) {
      add(r, r.geometry.point, 'Point');
      add(r, r.geometry.from, 'Début de segment');
      add(r, r.geometry.to, 'Fin de segment');
    }
    return buckets.values.map((items) {
      final first = items.first;
      return Marker(
        point: first.point,
        width: 48,
        height: 48,
        child: Semantics(
          button: true,
          label: items.length == 1
              ? '${first.record.title} · ${first.role}'
              : '${items.length} positions de signalements',
          child: Tooltip(
            message: items.length == 1
                ? '${first.record.title} · ${first.role}'
                : '${items.length} positions',
            child: Material(
              color: const Color(0xFFFFCC5C),
              shape: CircleBorder(
                side: BorderSide(color: Colors.brown.shade900, width: 2),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  if (items.length == 1) {
                    widget.onRecord(first.record);
                    return;
                  }
                  showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (sheet) => SafeArea(
                      child: ListView(
                        children: [
                          for (final item in items)
                            ListTile(
                              title: Text(item.record.title),
                              subtitle: Text(
                                '${item.record.roads.join(' / ')} · ${item.role}',
                              ),
                              onTap: () {
                                Navigator.pop(sheet);
                                widget.onRecord(item.record);
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                },
                child: Center(
                  child: items.length > 1
                      ? Text(
                          '${items.length}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : first.role == 'Point'
                      ? const Icon(Icons.traffic_outlined, color: Colors.black)
                      : Text(
                          first.role == 'Début de segment' ? 'A' : 'B',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final positionCount = widget.records
        .where((r) => r.geometry.hasCoordinates)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$positionCount fiches localisables. A/B : extrémités déclarées ; tracé routier inconnu.',
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: const LatLng(46.6, 2.5),
                initialZoom: 5,
                minZoom: mapMinZoom,
                maxZoom: mapMaxZoom,
                interactionOptions: InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  cursorKeyboardRotationOptions:
                      CursorKeyboardRotationOptions.disabled(),
                  keyboardOptions: const KeyboardOptions(
                    enableQERotating: false,
                  ),
                ),
                onMapReady: () => setState(() => _ready = true),
                onPositionChanged: (_, _) {
                  if (mounted) setState(() {});
                },
              ),
              children: [
                widget.tileLayer ??
                    buildTileLayer(context, style: widget.style),
                if (_ready) MarkerLayer(markers: _markers()),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MapScale(),
                      MapAttribution(style: widget.style),
                    ],
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Column(
                    children: [
                      MapControl(
                        tooltip: 'Zoomer sur le trafic',
                        icon: Icons.add,
                        onPressed: _ready ? () => _zoom(1) : null,
                      ),
                      const SizedBox(height: 8),
                      MapControl(
                        tooltip: 'Dézoomer sur le trafic',
                        icon: Icons.remove,
                        onPressed: _ready ? () => _zoom(-1) : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
