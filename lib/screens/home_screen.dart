import '../services/map_poi_groups.dart';
import 'road_sources_screen.dart';
import 'traffic_screen.dart';
import '../services/traffic_repository.dart';
import '../services/road_data_repository.dart';
import '../widgets/driving_speed.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../main.dart';
import '../models/location_alarm.dart';
import '../models/watch_status.dart';
import '../models/poi_type.dart';
import '../services/alarm_repository.dart';
import '../services/catalogue_importer.dart';
import '../services/department_arming.dart';
import '../services/native_bridge.dart';
import '../services/driving_settings.dart';
import '../services/driving_route_observer.dart';
import '../services/route_service.dart';
import '../models/vehicle_motion.dart';
import '../widgets/map_control.dart';
import '../services/native_reconciliation.dart';
import '../services/passage_log.dart';
import '../services/permission_service.dart';
import '../services/unit_controller.dart';
import '../theme/app_theme.dart';
import '../theme/poi_style.dart';
import '../widgets/alarm_card.dart';
import '../widgets/app_drawer.dart';
import '../widgets/map_pin.dart';
import '../widgets/map_scale.dart';
import '../widgets/map_tiles.dart';
import '../widgets/offline_notice.dart';
import 'location_picker_screen.dart';
import 'passage_log_screen.dart';
import 'reference_screen.dart';
import 'reliability_screen.dart';

/// Formats a metre distance the way a person would say it, in the chosen unit.
String formatDistance(double metres, [DistanceUnit unit = DistanceUnit.km]) =>
    formatDistanceWithUnit(metres, unit);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.tileLayer});
  final Widget? tileLayer;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
  static const _defaultPosition = LatLng(46.6, 2.5); // Continental France

  // The alarm sheet's resting and full sizes, shared with the map controls so
  // the two cannot drift apart.
  static const _sheetCollapsed = 0.13;
  static const _sheetExpanded = 0.62;
  // Past this the sheet owns the screen and the map controls step aside.
  static const _controlsFadeAt = 0.30;

  /// Ceiling for any transient message, in seconds.
  static const _maxNoticeSeconds = 5;

  final _repository = AlarmRepository();
  final _nativeBridge = NativeBridge();
  final _permissionService = PermissionService();
  final _mapController = MapController();

  List<LocationAlarm> _alarms = [];
  MapCamera? _groupCamera;
  List<LocationAlarm>? _groupAlarms;
  List<MapPoiGroup> _mapGroups = [];
  Timer? _viewportRefresh;
  LatLng _initialPosition = _defaultPosition;
  LatLng? _userLocation;
  double? _userAccuracy;
  double? _userSpeed;
  final _motion = VehicleMotion();
  final _clock = Stopwatch()..start();
  int _fixReceivedAt = 0, _fixAgeAtReceipt = 999999;
  final _driving = DrivingSettings.instance;
  static const _positionEvents =
      EventChannel('com.zaifears.locreminder/positions');
  StreamSubscription<dynamic>? _positionSubscription;
  bool _routeVisible = true,
      _appForeground = true,
      _mapReady = false,
      _followVehicle = true;
  PageRoute<dynamic>? _observedRoute;
  bool _appliedAutoFollow = true;
  final _routeService = RouteService();
  final _trafficRepository = TrafficRepository();
  DrivingRoute? _route;
  LatLng? _routeDestination;
  String? _destinationLabel;
  bool _calculatingRoute = false;
  StateSetter? _placesRefresh;
  int _routeRequest = 0;
  bool _userFixFresh = false;
  String _poiQuery = '';
  PoiType? _poiFilter;
  PermissionStatusSummary? _permissions;
  bool _loading = true;
  bool _importing = false;
  bool _savingImport = false;

  Future<void> _toggleReference() async {
    if (_importing || _savingImport) return;
    final reference = _alarms.where((a) => a.id.startsWith('mi:')).toList();
    if (reference.isEmpty) {
      _notify('Importer d’abord le catalogue de référence.');
      return;
    }
    final enable = reference.any((a) => !a.isActive);
    if (enable && !(await _permissionService.currentStatus()).isFullyReady) {
      if (mounted) {
        _notify('Terminer les autorisations dans « Fiabilité des alarmes ».');
      }
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(enable
                  ? 'Activer la référence'
                  : 'Mettre la référence en pause'),
              content: Text(
                  '${reference.length} lieux de référence. Les rayons et modes de répétition propres à chaque lieu sont conservés.\nLes autres sources et lieux personnels ne sont pas modifiés.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Annuler')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(enable ? 'Activer' : 'Mettre en pause')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => _savingImport = true);
    final previous = List<LocationAlarm>.of(_alarms);
    final changedBefore = previous
        .where((a) => a.id.startsWith('mi:') && a.isActive != enable)
        .toList();
    final changedAfter =
        changedBefore.map((a) => a.copyWith(isActive: enable)).toList();
    final byId = {for (final a in changedAfter) a.id: a};
    final updated = previous.map((a) => byId[a.id] ?? a).toList();
    var saved = false;
    var nativeAttempted = false;
    try {
      await _repository.saveAll(updated);
      saved = true;
      if (changedAfter.isNotEmpty) {
        nativeAttempted = true;
        await _nativeBridge.syncSelectedAlarms(changedAfter);
      }
      if (mounted) setState(() => _alarms = updated);
      await _syncLocationWatch();
      if (mounted) {
        _notify(enable
            ? 'Lieux de référence activés.'
            : 'Lieux de référence en pause.');
      }
    } catch (_) {
      var recovered = true;
      if (saved) {
        try {
          await _repository.saveAll(previous);
        } catch (_) {
          recovered = false;
        }
      }
      if (nativeAttempted) {
        try {
          await _nativeBridge.syncSelectedAlarms(changedBefore);
        } catch (_) {
          recovered = false;
        }
      }
      if (mounted) {
        _notify(recovered
            ? 'Échec de synchronisation : état précédent rétabli.'
            : 'Synchronisation incomplète : vérifier les lieux avant utilisation.');
      }
    } finally {
      if (mounted) setState(() => _savingImport = false);
    }
  }

  Future<void> _importCatalogue() async {
    if (_importing) return;
    _importing = true;
    try {
      final selected = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
              title: Text('Importer des lieux'),
              subtitle: Text('Les nouveaux points restent désarmés.')),
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Radars — ministère'),
              subtitle: const Text('Catalogue continental embarqué'),
              onTap: () => Navigator.pop(sheet, 'reference')),
          ListTile(
              leading: const Icon(Icons.train_outlined),
              title: const Text('Passages à niveau — SNCF'),
              subtitle: const Text(
                  'Par département · signalement véhicules surbaissés'),
              onTap: () => Navigator.pop(sheet, 'railway')),
          ListTile(
              leading: const Icon(Icons.waves),
              title: const Text('Dangers routiers — OpenStreetMap'),
              subtitle: const Text(
                  'Ralentisseurs, vibreurs et rétrécissements · connexion requise'),
              onTap: () => Navigator.pop(sheet, 'osm')),
          ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('Fichier catalogue JSON'),
              onTap: () => Navigator.pop(sheet, 'file')),
        ]))),
      );
      if (selected == null || !mounted) return;
      final List<LocationAlarm> incoming;
      if (selected == 'railway' || selected == 'osm') {
        final points = await Navigator.of(context).push<List<LocationAlarm>>(
            MaterialPageRoute(
                builder: (_) => RoadSourcesScreen(
                    kind: selected == 'railway'
                        ? RoadDataKind.railway
                        : RoadDataKind.calming)));
        if (points == null || !mounted) return;
        incoming = points;
      } else {
        final text = selected == 'reference'
            ? await rootBundle
                .loadString('assets/catalogue/catalogue_reference.json')
            : await _nativeBridge.pickCatalogue();
        if (text == null || !mounted) return;
        incoming = await CatalogueImporter.parseAsync(text);
      }
      if (!mounted) return;
      final existingIds = _alarms.map((a) => a.id).toSet();
      final newCount =
          incoming.where((a) => !existingIds.contains(a.id)).length;
      final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Prévisualisation'),
                content: Text(
                    '${incoming.length} lieux lus.\n$newCount nouveaux lieux.\n${incoming.length - newCount} identifiants déjà présents : conservés sans modification.\n\nAucune alarme ne sera activée. Les données cartographiques peuvent être anciennes ; un cercle ne reconnaît pas les routes ni le sens de circulation.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Importer désactivés')),
                ],
              ));
      if (confirm != true || !mounted) return;
      // Recalculate after the preview, so changes made while picking a file
      // are not overwritten. Inactive imports never touch the native store.
      setState(() => _savingImport = true);
      final merged = CatalogueImporter.merge(_alarms, incoming);
      final added = merged.length - _alarms.length;
      await _repository.saveAll(merged);
      if (!mounted) return;
      setState(() => _alarms = merged);
      _notify(
          '$added lieux importés, désarmés. Rayon d’anticipation réglable par lieu.');
    } on FormatException catch (e) {
      if (mounted) _notify('Import refusé : ${e.message}');
    } catch (_) {
      if (mounted) {
        _notify(
            'Import impossible. Les alarmes actives ne sont pas modifiées.');
      }
    } finally {
      _importing = false;
      if (mounted) setState(() => _savingImport = false);
    }
  }

  bool _locating = false;
  MapStyle _mapStyle = MapStyle.standard;

  /// How far the alarm sheet is drawn up, as a fraction of screen height.
  /// Starts at the collapsed size the sheet itself declares.
  double _sheetExtent = _sheetCollapsed;
  bool _alarmRinging = false;

  /// Keeps the blue dot and the distance on each alarm card moving while the
  /// app is open and something is armed.
  ///
  /// It reads the fix the watch service has already taken rather than asking
  /// the platform for one of its own, so watching your own progress costs no
  /// battery beyond what the alarm was spending anyway. Without it the dot
  /// was frozen wherever it stood when the screen was opened — which nobody
  /// notices while the map is drawing, and everybody notices when the map is
  /// blank and this readout is the only thing left saying how far the stop
  /// still is.
  Timer? _tracker;

  /// Last position at which the department was checked, and the department
  /// currently armed by that check.
  LatLng? _lastArmCheck;
  String? _armedDepartment;
  Map<Object?, Object?> _passage = const {};
  WatchStatus _watchStatus = const WatchStatus("unknown");
  Future<void> _refreshPassage() async {
    try {
      final status = await _nativeBridge.getPassageStatus();
      if (mounted && !mapEquals(_passage, status)) {
        setState(() => _passage = status);
      }
      _recordPassage(status);
      final watch = WatchStatus.fromMap(await _nativeBridge.getWatchStatus());
      if (mounted &&
          (watch.state != _watchStatus.state ||
              watch.armedCount != _watchStatus.armedCount)) {
        setState(() => _watchStatus = watch);
      }
    } catch (_) {/* Legacy native engine has no passage status. */}
  }

  /// Keeps the diagnostic log in step with what the native watcher reports.
  /// Only transitions are written; see [PassageLog.record].
  void _recordPassage(Map<Object?, Object?> status) {
    final stage = status['stage'] as String?;
    final label = status['label'] as String?;
    if (stage == null || label == null) return;
    unawaited(PassageLog.record(PassageLogEntry(
      at: DateTime.now(),
      label: label,
      stage: stage,
      distanceMetres: (status['distance'] as num?)?.toDouble(),
      accuracyMetres: (status['accuracy'] as num?)?.toDouble(),
      stale: status['stale'] == true,
    )));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _driving.addListener(_onDrivingSettings);
    _driving.load();
    _bootstrap();
  }

  @override
  void dispose() {
    _stopTracking();
    _viewportRefresh?.cancel();
    _routeRequest++;
    _routeService.close();
    _trafficRepository.close();
    drivingRouteObserver.unsubscribe(this);
    _driving.removeListener(_onDrivingSettings);
    _nativeBridge.setDrivingScreen(false).catchError((_) {});
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _observedRoute) {
      drivingRouteObserver.unsubscribe(this);
      _observedRoute = route;
      drivingRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _stopTracking();
    _applyScreenPolicy();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _updateTracking();
    _applyScreenPolicy();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appForeground = state == AppLifecycleState.resumed;
    if (_appForeground) {
      _reconcileTriggeredAlarms();
      _refreshRingingState();
      _refreshPermissions();
      _locateUser();
      _updateTracking();
    } else {
      _stopTracking();
    }
    _applyScreenPolicy();
  }

  void _onDrivingSettings() {
    if (!mounted) return;
    setState(() {
      if (_appliedAutoFollow != _driving.autoFollow) {
        _followVehicle = _driving.autoFollow;
      }
      _appliedAutoFollow = _driving.autoFollow;
    });
    if (_mapReady && !_driving.headingUp) _mapController.rotate(0);
    _applyScreenPolicy();
    _centerVehicle();
  }

  void _applyScreenPolicy() {
    _nativeBridge
        .setDrivingScreen(
            _routeVisible && _appForeground && _driving.keepScreenAwake)
        .catchError((_) {});
  }

  void _updateTracking() {
    if (!_routeVisible || !_appForeground || !mounted) return;
    _applyScreenPolicy();
    _positionSubscription ??=
        _positionEvents.receiveBroadcastStream().listen((event) {
      if (event is Map) _acceptMapFix(Map<Object?, Object?>.from(event));
    }, onError: (_) {});
    _tracker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshPassage();
      _locateUser();
      final fresh = _fixAge <= 5000 && (_userAccuracy ?? 999) <= 50;
      if (mounted && fresh != _userFixFresh) {
        setState(() => _userFixFresh = fresh);
      }
    });
  }

  int get _fixAge =>
      _fixAgeAtReceipt + _clock.elapsedMilliseconds - _fixReceivedAt;
  void _stopTracking() {
    _tracker?.cancel();
    _tracker = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _acceptMapFix(Map<Object?, Object?> row) {
    final fix = VehicleFix.parse(row);
    if (fix == null || !_motion.accept(fix) || !mounted) return;
    setState(() {
      _fixAgeAtReceipt = fix.ageMillis;
      _fixReceivedAt = _clock.elapsedMilliseconds;
      _userLocation = fix.position;
      _initialPosition = fix.position;
      _userAccuracy = fix.accuracy;
      _userFixFresh = fix.ageMillis <= 5000 && fix.accuracy <= 50;
      _userSpeed = _motion.speedMps;
    });
    _centerVehicle();
    unawaited(_maybeAutoArmDepartment());
  }

  void _centerVehicle({bool force = false}) {
    if (!_mapReady ||
        !_routeVisible ||
        !_appForeground ||
        _userLocation == null ||
        !_userFixFresh ||
        (!_followVehicle && !force)) {
      return;
    }
    final rotation = _driving.headingUp ? -(_motion.bearing ?? 0.0) : 0.0;
    final zoom = force
        ? 16.0
        : _mapController.camera.zoom < 10
            ? 15.0
            : _mapController.camera.zoom;
    _mapController.moveAndRotate(_userLocation!, zoom, rotation);
  }

  /// Everything the map needs before it can be shown.
  ///
  /// The `finally` is the point: each step here talks to storage or to the
  /// platform, and anything that throws on the way used to leave `_loading`
  /// true forever — a permanent spinner instead of a map, on a device where
  /// one of these calls happens to misbehave. Clearing the flag regardless
  /// means the worst case is a map missing some state, which the app already
  /// recovers from on the next resume.
  Future<void> _bootstrap() async {
    try {
      final style = await MapStyleStore.load();
      if (mounted) setState(() => _mapStyle = style);
      var alarms = await _repository.loadAll();
      if (mounted && _repository.rejectedRecords > 0) {
        _notify('${_repository.rejectedRecords} lieux illisibles conservés dans une copie locale de récupération.', seconds: 6);
      }
      final hasCatalogue = alarms.any((a) => a.id.startsWith('mi:'));
      if (hasCatalogue) {
        final text = await rootBundle
            .loadString('assets/catalogue/catalogue_reference.json');
        alarms = CatalogueImporter.merge(alarms, await CatalogueImporter.parseAsync(text));
        await _repository.saveAll(alarms);
      }
      if (mounted) setState(() => _alarms = alarms);
      {
        final passageEntries =
            alarms.where((a) => a.isActive && a.repeatOnEveryEntry).toList();
        if (passageEntries.isNotEmpty) {
          try {
            await _nativeBridge.syncSelectedAlarms(passageEntries);
          } catch (_) {
            if (mounted) {
              _notify(
                  'La mise à jour de la surveillance a échoué. Vérifier son état dans Fiabilité.');
            }
          }
        }
      }
      await _reconcileTriggeredAlarms();
      await _refreshRingingState();
      await _refreshPermissions();
      await _locateUser();
      await _refreshPassage();
      _updateTracking();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshPermissions() async {
    final status = await _permissionService.currentStatus();
    if (mounted) setState(() => _permissions = status);
  }

  /// Shows a transient message, replacing any message already on screen.
  ///
  /// Every notice goes through here for two reasons. SnackBars *queue* by
  /// default, so a burst of them plays back one after another and the last is
  /// still sitting there long after the action that caused it — which reads
  /// as a stuck message rather than a slow one. And the longest message needs
  /// a ceiling: [_maxNoticeSeconds] is long enough to read a two-line
  /// sentence and short enough not to outstay the moment.
  void _notify(String message, {SnackBarAction? action, int seconds = 3}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        duration: Duration(seconds: seconds.clamp(1, _maxNoticeSeconds)),
      ),
    );
  }

  /// Keeps the native watch service running exactly while something is armed.
  /// Called after every change to the alarm list so the service never lingers
  /// with nothing to watch, and never stops while an alarm still needs it.
  /// Sends every armed-state change to the watcher before anything else is
  /// written, so the two stores cannot disagree for longer than one call.
  Future<void> _pushArmingChanges(
    List<LocationAlarm> before,
    List<LocationAlarm> after,
  ) async {
    final changed = NativeReconciliation.armingChanges(before, after);
    if (changed.isEmpty) return;
    try {
      await _nativeBridge.syncSelectedAlarms(changed);
    } on PlatformException catch (e) {
      if (mounted) {
        _notify('Armement non transmis (${e.code}). Réessaie.', seconds: 5);
      }
      rethrow;
    }
  }

  Future<void> _syncLocationWatch() async {
    var shouldWatch = _alarms.any((a) => a.isActive);
    _updateTracking();
    try {
      // Preserved native rows must not be stopped just because Flutter does not own them.
      if (!shouldWatch) shouldWatch = (await _nativeBridge.getActiveAlarmIds()).isNotEmpty;
      if (shouldWatch) {
        await _nativeBridge.startLocationWatch();
      } else {
        await _nativeBridge.stopLocationWatch();
      }
    } on PlatformException catch (e) {
      if (shouldWatch) {
        _notify(
          'Le suivi en arrière-plan n’a pas pu démarrer (${e.code}). Les '
          'alertes peuvent être retardées — vérifie les autorisations.',
          seconds: 5,
        );
      }
    }
  }

  /// Updates the blue dot, and on [recenter] moves the map to it.
  ///
  /// A tap on the locate button asks for a *fresh* fix: the cached one the
  /// background refresh uses can be hours stale or missing entirely, which
  /// made the button appear to do nothing at all right after a reboot.
  Future<void> _locateUser({bool recenter = false}) async {
    if (recenter && _locating) return;
    if (recenter) setState(() => _locating = true);

    try {
      final fix = recenter
          ? await _nativeBridge.getCurrentLocation()
          : await _nativeBridge.getLastKnownLocation();
      if (fix == null) {
        if (recenter && mounted) await _reportLocateFailure();
        return;
      }
      _acceptMapFix(fix);
      if (recenter && mounted) {
        setState(() => _followVehicle = true);
        _centerVehicle(force: true);
        if (!_userFixFresh) await _reportLocateFailure();
      }
    } catch (_) {
      // Keep the default position; the user can still pan and search.
      if (recenter && mounted) await _reportLocateFailure();
    } finally {
      if (recenter && mounted) setState(() => _locating = false);
    }
  }

  /// Says why locating failed, and offers the fix when it is the usual one.
  Future<void> _reportLocateFailure() async {
    final locationOn = await _nativeBridge.isLocationEnabled();
    if (!mounted) return;

    _notify(
      locationOn
          ? 'Position GPS introuvable. Réessaie à l’extérieur.'
          : 'La localisation est désactivée.',
      action: locationOn
          ? null
          : SnackBarAction(
              label: 'Activer',
              onPressed: _nativeBridge.openLocationSettings,
            ),
    );
  }

  bool _reconciling = false;
  bool _nativeRepairNotified = false;

  /// Receipts, repair and acknowledgement are separate from missing native rows.
  Future<void> _reconcileTriggeredAlarms() async {
    if (_savingImport || _reconciling || _alarms.isEmpty) return;
    _reconciling = true;
    final inspected = List<LocationAlarm>.of(_alarms);
    try {
      final state = await _nativeBridge.getAlarmState();
      if (!mounted) return;
      if (state.corrupt) {
        if (state.activeIds.isNotEmpty) await _nativeBridge.startLocationWatch();
        if (!_nativeRepairNotified) {
          _nativeRepairNotified = true;
          _notify(
            'Copie de surveillance endommagée. Ouvre Fiabilité pour la réparer.',
            seconds: 6,
            action: SnackBarAction(
              label: 'Réparer',
              onPressed: _repairNativeStore,
            ),
          );
        }
        return;
      }
      _nativeRepairNotified = false;
      final consumed = state.receipts.keys.toSet();
      final missing =
          NativeReconciliation.toRepair(
                inspected,
                state.activeIds,
                consumedIds: consumed,
              )
              .where((old) => _alarms.any((current) => identical(current, old)))
              .toList();
      if (missing.isNotEmpty) await _nativeBridge.syncSelectedAlarms(missing);
      if (!mounted) return;
      final delivered = NativeReconciliation.alreadyRang(
        inspected,
        state.activeIds,
        consumedIds: consumed,
      ).toSet();
      final accepted = <String, String>{};
      final reconciled = _alarms.map((alarm) {
        if (!delivered.contains(alarm)) return alarm;
        accepted[alarm.id] = state.receipts[alarm.id]!;
        return alarm.copyWith(isActive: false);
      }).toList();
      if (accepted.isNotEmpty) {
        // Persist the inactive UI before removing the only positive native receipt.
        final beforeSave = _alarms;
        setState(() => _alarms = reconciled);
        try {
          await _repository.saveAll(reconciled);
        } catch (_) {
          if (mounted && identical(_alarms, reconciled)) {
            setState(() => _alarms = beforeSave);
          }
          rethrow;
        }
        await _nativeBridge.acknowledgeAlarmReceipts(accepted);
        if (mounted) _notify('Rappel ponctuel transmis par le service.');
      }
      // A previous process may have persisted the inactive UI just before dying.
      final persistedInactive = (await _repository.loadAll())
          .where((p) => !p.isActive)
          .map((p) => p.id)
          .toSet();
      final alreadyInactive = {
        for (final alarm in _alarms)
          if (!alarm.isActive &&
              persistedInactive.contains(alarm.id) &&
              state.receipts.containsKey(alarm.id) &&
              !accepted.containsKey(alarm.id))
            alarm.id: state.receipts[alarm.id]!,
      };
      if (alreadyInactive.isNotEmpty) {
        await _nativeBridge.acknowledgeAlarmReceipts(alreadyInactive);
      }
      if (mounted) await _syncLocationWatch();
    } catch (_) {
      if (mounted) {
        _notify(
          'Synchronisation de surveillance impossible. Les lieux sont conservés.',
        );
      }
    } finally {
      _reconciling = false;
    }
  }

  bool _repairingNative = false;
  Future<void> _repairNativeStore() async {
    if (_repairingNative) return;
    _repairingNative = true;
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Réparer la surveillance ?'),
          scrollable: true,
          content: const Text(
            'La copie de surveillance sera reconstruite depuis tes lieux enregistrés. '
            'Les autres points natifs valides seront conservés. Une copie locale de l’état précédent '
            'restera disponible pour récupération. Les rappels ponctuels sans reçu lisible seront à vérifier.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Réparer'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      try {
        final state = await _nativeBridge.getAlarmState();
        if (!mounted) return;
        if (!state.corrupt) {
          _notify('La copie de surveillance est déjà valide.');
          return;
        }
        final delivered = NativeReconciliation.alreadyRang(
          _alarms,
          state.activeIds,
          consumedIds: state.receipts.keys.toSet(),
        ).toSet();
        final repaired = _alarms
            .map((p) => delivered.contains(p) ? p.copyWith(isActive: false) : p)
            .toList();
        await _repository.saveAll(repaired);
        if (!mounted) return;
        setState(() => _alarms = repaired);
        await _nativeBridge.repairAlarmStore(repaired);
        _nativeRepairNotified = false;
        await _syncLocationWatch();
        if (mounted) _notify('Copie de surveillance réparée.');
      } catch (_) {
        if (mounted) {
          _notify('Réparation impossible. La copie précédente est conservée.');
        }
      }
    } finally {
      _repairingNative = false;
    }
  }

  Future<void> _refreshRingingState() async {
    final ringing = await _nativeBridge.isAlarmRinging();
    if (mounted) setState(() => _alarmRinging = ringing);
  }

  Future<void> _stopAlarm() async {
    await _nativeBridge.stopAlarm();
    await _reconcileTriggeredAlarms();
    await _refreshRingingState();
  }

  /// Opens the picker. [fromSearch] is set by the search field at the top of
  /// the map, which is a request to type — so the keyboard comes up with the
  /// screen rather than waiting for a second tap on a field the user has in
  /// effect already tapped.
  Future<void> _addAlarm({bool fromSearch = false}) async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialCenter: _userLocation ?? _initialPosition,
          autofocusSearch: fromSearch,
          travelSpeed: _userSpeed,
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final alarm = LocationAlarm(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: picked.label,
      latitude: picked.latitude,
      longitude: picked.longitude,
      radiusMeters: picked.radiusMeters,
      isActive: true,
      createdAt: DateTime.now(),
      repeatDays: picked.repeatDays,
      repeatOnEveryEntry: picked.repeatOnEveryEntry,
      poiType: picked.poiType,
      note: picked.note,
      positionStatus: picked.positionStatus,
      positionAccuracyMeters: picked.positionAccuracyMeters,
      speedLimitKmh: picked.speedLimitKmh,
      adaptiveRadius: picked.adaptiveRadius,
      referenceSpeedKmh: picked.referenceSpeedKmh,
      roadContext: picked.roadContext,
      travelBearingDegrees: picked.travelBearingDegrees,
    );

    final registered = await _register(alarm);
    if (!registered || !mounted) return;

    setState(() => _alarms = [..._alarms, alarm]);
    await _repository.saveAll(_alarms);
    await _syncLocationWatch();

    _mapController.move(LatLng(alarm.latitude, alarm.longitude), 14);
    if (!mounted) return;

    // Arrival means crossing into the radius, so an alarm set for somewhere
    // you are already standing stays silent until you leave and come back.
    // Say so rather than letting it look broken.
    final here = _userLocation;
    final alreadyInside = here != null &&
        const Distance()(here, LatLng(alarm.latitude, alarm.longitude)) <=
            alarm.radiusMeters;

    final schedule = alarm.repeats ? ' · ${alarm.scheduleLabel}' : '';
    _notify(
      alreadyInside
          ? 'Lieu enregistré — tu es déjà dans cette zone : l’alerte sonnera '
              'quand tu en sortiras, puis quand tu y reviendras.'
          : 'Lieu enregistré : ${alarm.label}$schedule',
      seconds: alreadyInside ? 5 : 3,
    );
  }

  /// Puts the map around a new alarm on the phone while there is still a
  /// connection to fetch it with.
  ///
  /// Registers the alarm natively, surfacing failures instead of leaving an
  /// alarm that looks armed in the list but the watcher never learned about.
  Future<bool> _register(LocationAlarm alarm) async {
    try {
      await _nativeBridge.addAlarm(alarm);
      return true;
    } on PlatformException catch (e) {
      _notify('Lieu non enregistré : ${e.message ?? e.code}', seconds: 5);
      return false;
    }
  }

  Future<void> _toggleAlarm(LocationAlarm alarm) async {
    if (alarm.isActive) {
      try {
        await _nativeBridge.removeAlarm(alarm.id);
      } on PlatformException catch (_) {
        if (mounted) {
          _notify('Mise en pause impossible. Le lieu reste armé. Réessaie.');
        }
        return;
      }
    } else {
      final registered = await _register(alarm);
      if (!registered) return;
    }
    if (!mounted) return;

    final updated = alarm.copyWith(isActive: !alarm.isActive);
    setState(() {
      _alarms = _alarms.map((a) => a.id == alarm.id ? updated : a).toList();
    });
    await _repository.saveAll(_alarms);
    await _syncLocationWatch();
  }

  Future<void> _deleteAlarm(LocationAlarm alarm) async {
    final index = _alarms.indexWhere((a) => a.id == alarm.id);
    try {
      await _nativeBridge.removeAlarm(alarm.id);
    } on PlatformException catch (_) {
      if (mounted) {
        _notify('Suppression impossible. Le lieu est conservé. Réessaie.');
      }
      return;
    }
    if (!mounted) return;

    setState(() => _alarms = _alarms.where((a) => a.id != alarm.id).toList());
    _notify(
      '${alarm.label} supprimé',
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () => _restoreAlarm(alarm, index),
      ),
      seconds: 5,
    );
    await _repository.saveAll(_alarms);
    await _syncLocationWatch();
  }

  /// Opens the picker pre-populated with [alarm]'s current values so the
  /// user can change any field — including the location itself.
  ///
  /// On save the old native alarm is removed and a new one registered under
  /// the same ID, which is indistinguishable from a delete + create to the
  /// watch service. Keeping the ID preserves the alarm's position in the
  /// list and its creation timestamp.
  ///
  /// Suggested by @kiinami — https://github.com/zaifears/locreminder/issues/10
  Future<void> _editAlarm(LocationAlarm alarm) async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialCenter: LatLng(alarm.latitude, alarm.longitude),
          travelSpeed: _userSpeed,
          editingAlarm: alarm,
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final updated = alarm.copyWith(
      label: picked.label,
      latitude: picked.latitude,
      longitude: picked.longitude,
      radiusMeters: picked.radiusMeters,
      repeatDays: picked.repeatDays,
      repeatOnEveryEntry: picked.repeatOnEveryEntry,
      poiType: picked.poiType,
      note: picked.note,
      positionStatus: picked.positionStatus,
      positionAccuracyMeters: picked.positionAccuracyMeters,
      clearPositionAccuracy: picked.positionAccuracyMeters == null,
      speedLimitKmh: picked.speedLimitKmh,
      adaptiveRadius: picked.adaptiveRadius,
      referenceSpeedKmh: picked.referenceSpeedKmh,
      roadContext: picked.roadContext,
      travelBearingDegrees: picked.travelBearingDegrees,
      clearTravelBearing: picked.travelBearingDegrees == null,
      // An emptied field means "no known limit", not "keep the old one".
      clearSpeedLimit: picked.speedLimitKmh == null,
    );

    if (updated.hasSameEditableValues(alarm)) return;

    // Register the updated alarm on the native side. AlarmStore.save()
    // replaces by ID and clears ArrivalState so arrival is evaluated fresh.
    if (alarm.isActive) {
      final registered = await _register(updated);
      if (!registered || !mounted) return;
    }

    setState(() {
      _alarms = _alarms.map((a) => a.id == alarm.id ? updated : a).toList();
    });
    await _repository.saveAll(_alarms);
    await _syncLocationWatch();

    _mapController.move(LatLng(updated.latitude, updated.longitude), 14);
    if (!mounted) return;

    final here = _userLocation;
    final alreadyInside = updated.isActive &&
        here != null &&
        const Distance()(here, LatLng(updated.latitude, updated.longitude)) <=
            updated.radiusMeters;

    final schedule = updated.repeats ? ' · ${updated.scheduleLabel}' : '';
    _notify(
      alreadyInside
          ? 'Lieu modifié — tu es déjà dans cette zone : l’alerte sonnera '
              'quand tu en sortiras, puis quand tu y reviendras.'
          : 'Lieu modifié : ${updated.label}$schedule',
      seconds: alreadyInside ? 5 : 3,
    );
  }

  Future<void> _restoreAlarm(LocationAlarm alarm, int index) async {
    if (alarm.isActive) {
      final registered = await _register(alarm);
      if (!registered) return;
    }
    if (!mounted) return;

    setState(() {
      final restored = [..._alarms];
      restored.insert(index.clamp(0, restored.length), alarm);
      _alarms = restored;
    });
    await _repository.saveAll(_alarms);
    await _syncLocationWatch();
  }

  bool get _mapControlsHidden => _sheetExtent > _controlsFadeAt;

  /// Leave system gesture space beneath the map controls.
  double _mapControlsBottomInset(BuildContext context) =>
      MediaQuery.of(context).padding.bottom + 16;

  /// What the pin colours mean, and how many places of each kind are saved.
  ///
  /// Counted from the alarms actually on this phone rather than from the
  /// catalogue file, so the legend answers "what am I looking at here"
  /// including places the user added, edited or deleted.
  Future<void> _showLegend() async {
    final counts = <PoiType, int>{};
    for (final alarm in _alarms) {
      counts.update(alarm.poiType, (n) => n + 1, ifAbsent: () => 1);
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text('Couleurs de la carte', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Un lieu en pause garde sa couleur, en plus clair. '
                'Le nombre indique les lieux enregistrés sur ce téléphone.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (final type in PoiType.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor:
                        PoiStyle.of(type).color.withValues(alpha: 0.16),
                    child: Icon(PoiStyle.of(type).icon,
                        color: PoiStyle.readable(type, scheme)),
                  ),
                  title: Text(type.label),
                  trailing: Text('${counts[type] ?? 0}'),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Arms the department the phone is in, once per movement of more than
  /// 5 km. The check runs on every location fix, so it has to be cheap: two
  /// numbers compared before any list is walked.
  Future<void> _maybeAutoArmDepartment() async {
    if (!await DepartmentArming.autoEnabled()) return;
    final here = _userLocation;
    if (here == null ||
        !_userFixFresh ||
        _userAccuracy == null ||
        !_userAccuracy!.isFinite ||
        _userAccuracy! > 100) {
      return;
    }
    final lastLat = _lastArmCheck?.latitude;
    final lastLon = _lastArmCheck?.longitude;
    if (lastLat != null && lastLon != null) {
      final moved = const Distance()(LatLng(lastLat, lastLon), here);
      if (moved < 5000) return;
    }
    _lastArmCheck = here;
    final code =
        DepartmentArming.departmentAt(_alarms, here.latitude, here.longitude);
    if (code == null || code == _armedDepartment) return;
    final updated = DepartmentArming.armOnly(_alarms, code);
    if (identical(updated, _alarms)) return;
    try {
      await _pushArmingChanges(_alarms, updated);
    } on PlatformException catch (_) {
      _lastArmCheck = null;
      if (mounted) {
        _notify(
            'Armement automatique impossible. Réessaie depuis les points de référence.');
      }
      return;
    }
    if (!mounted) return;
    _armedDepartment = code;
    setState(() => _alarms = updated);
    await _repository.saveAll(updated);
    await _syncLocationWatch();
    _updateTracking();
    if (mounted) _notify('Département $code armé pour ce trajet.', seconds: 4);
  }

  Future<void> _openReference() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReferenceScreen(
          alarms: _alarms,
          onChanged: (updated) async {
            if (!mounted) return;
            // The watcher owns the arming; the list here only mirrors it. A
            // change that stops at this side is an app that shows a place as
            // watched while nothing is watching it.
            await _pushArmingChanges(_alarms, updated);
            if (!mounted) return;
            setState(() => _alarms = updated);
            await _repository.saveAll(updated);
            await _syncLocationWatch();
            _updateTracking();
          },
        ),
      ),
    );
  }

  Future<void> _pickMapStyle() async {
    final picked = await showMapStyleSheet(context, _mapStyle);
    if (picked == null || !mounted) return;
    setState(() => _mapStyle = picked);
    await MapStyleStore.save(picked);
  }

  void _focusAlarm(LocationAlarm alarm) {
    setState(() => _followVehicle = false);
    _mapController.move(LatLng(alarm.latitude, alarm.longitude), 15);
  }

  double? _distanceTo(LocationAlarm alarm) {
    final here = _userLocation;
    if (here == null) return null;
    // latlong2's Distance is a pure-Dart haversine, so this needs no plugin.
    return const Distance()(here, LatLng(alarm.latitude, alarm.longitude));
  }

  List<Marker> get _markers {
    final camera = _mapReady ? _mapController.camera : null;
    if (camera != null &&
        (!identical(camera, _groupCamera) ||
            !identical(_alarms, _groupAlarms))) {
      _mapGroups = MapPoiGroups.select(_alarms, camera);
      _groupCamera = camera;
      _groupAlarms = _alarms;
    }
    final groups = camera == null ? const <MapPoiGroup>[] : _mapGroups;
    final markers = groups.map((group) {
      if (group.alarms.length > 1) return _clusterMarker(group);
      final alarm = group.alarms.single;
      return Marker(
        point: LatLng(alarm.latitude, alarm.longitude),
        width: 48,
        height: 48,
        // flutter_map's alignment reads the other way round from the
        // usual Flutter one: topCenter puts the whole widget *above* the
        // point, which is what plants the pin's tip on the coordinate.
        // bottomCenter put the pin's top edge on the point instead, so at
        // a wide zoom the pin hung a full 44 px below its own circle.
        alignment: Alignment.topCenter,
        // Counter-rotate against the map so two-finger rotation doesn't
        // spin the pins — they stay upright like real map pins.
        rotate: true,
        child: GestureDetector(
          onTap: () => _showAlarmPreview(alarm),
          excludeFromSemantics: true,
          child: Semantics(
            label:
                '${alarm.poiType.label} · ${alarm.label} · ${alarm.isActive ? "armé" : "en pause"}',
            button: true,
            onTap: () => _showAlarmPreview(alarm),
            child: MapPin(
              size: 48,
              icon: PoiStyle.of(alarm.poiType).icon,
              paused: !alarm.isActive,
              // The pin carries the kind of place, not just whether it is
              // armed: with 859 of them on screen a single blue says nothing
              // about which one is the red light ahead.
              color: alarm.isActive
                  ? PoiStyle.of(alarm.poiType).color
                  : PoiStyle.pausedColor(
                      alarm.poiType, Theme.of(context).colorScheme),
              borderColor: PoiStyle.pinBorder(Theme.of(context).colorScheme),
            ),
          ),
        ),
      );
    }).toList();

    final userLocation = _userLocation;
    if (userLocation != null) {
      markers.add(
        Marker(
          point: userLocation,
          width: 22,
          height: 22,
          rotate: true,
          child: Builder(builder: (context) {
            final bearing = _motion.bearing;
            return Transform.rotate(
                angle: ((bearing ?? 0) + MapCamera.of(context).rotation) *
                    3.141592653589793 /
                    180,
                child: Container(
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _userFixFresh
                            ? RedAlertSemantics.of(context).userLocation
                            : Colors.grey,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(blurRadius: 3, color: Colors.black26)
                        ]),
                    child: bearing == null
                        ? null
                        : const Icon(Icons.navigation,
                            color: Colors.white, size: 14)));
          }),
        ),
      );
    }
    return markers;
  }

  Marker _clusterMarker(MapPoiGroup group) => Marker(
      point: group.anchor,
      width: 54,
      height: 54,
      rotate: true,
      child: Semantics(
          label: '${group.alarms.length} lieux regroupés, ${group.armed} armés',
          button: true,
          onTap: () => _openMapGroup(group),
          child: Tooltip(
              message: '${group.alarms.length} lieux · toucher pour explorer',
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                shape: CircleBorder(
                    side: BorderSide(
                        color: group.armed > 0
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        width: 2)),
                elevation: 2,
                child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _openMapGroup(group),
                    child: Center(
                        child: Text('${group.alarms.length}',
                            style: Theme.of(context).textTheme.titleMedium))),
              ))));

  void _openMapGroup(MapPoiGroup group) {
    setState(() => _followVehicle = false);
    final points =
        group.alarms.map((p) => LatLng(p.latitude, p.longitude)).toList();
    if (_mapController.camera.zoom >= 17 ||
        points.every((p) => p == points.first)) {
      showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
              child: ListView.builder(
                  itemCount: group.alarms.length,
                  itemBuilder: (_, i) {
                    final alarm = group.alarms[i];
                    return ListTile(
                        leading: Icon(PoiStyle.of(alarm.poiType).icon),
                        title: Text(alarm.label),
                        subtitle: Text(alarm.poiType.label),
                        onTap: () {
                          Navigator.pop(sheet);
                          _editAlarm(alarm);
                        });
                  })));
    } else {
      _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(70),
          maxZoom: 17));
    }
  }

  void _showAlarmPreview(LocationAlarm alarm) {
    final unit = LocReminderApp.unitOf(context).value;
    final distance = _distanceTo(alarm);
    _notify(
      distance == null
          ? '${alarm.label} · ${alarm.isActive ? "armé" : "en pause"} · zone de ${formatRadiusWithUnit(alarm.radiusMeters, unit)}'
          : '${alarm.label} · ${alarm.isActive ? "armé" : "en pause"} · à ${formatDistance(distance, unit)}',
    );
  }

  List<CircleMarker> get _circles {
    final circles = _alarms
        .where((a) => a.isActive)
        .map(
          (alarm) => CircleMarker(
            point: LatLng(alarm.latitude, alarm.longitude),
            radius: alarm.radiusMeters,
            useRadiusInMeter: true,
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            borderColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
            borderStrokeWidth: 2,
          ),
        )
        .toList();

    // How sure the fix actually is. Without this the dot claims a precision
    // it may not have — indoors it can be hundreds of metres out, which
    // matters here, because that is also roughly the scale of the radius
    // people pick. Below the dot's own size it would just be noise.
    final here = _userLocation;
    final accuracy = _userAccuracy;
    if (here != null && accuracy != null && accuracy > 30) {
      circles.insert(
        0,
        CircleMarker(
          point: here,
          radius: accuracy,
          useRadiusInMeter: true,
          color: Colors.blueAccent.withValues(alpha: 0.10),
          borderColor: Colors.blueAccent.withValues(alpha: 0.35),
          borderStrokeWidth: 1,
        ),
      );
    }
    return circles;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _savingImport) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      drawer: AppDrawer(
        onRepairStore: _repairNativeStore,
          placeCount: _alarms.length,
          armedCount: _alarms.where((a) => a.isActive).length,
          watchLabel: _repository.rejectedRecords > 0 ? '${_watchStatus.label} · lieux à vérifier' : _watchStatus.label,
          onPlaces: _openPlaces,
          onAddPlace: _addAlarm,
          onRoute: _startRoute,
          onTraffic: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => TrafficScreen(repository: _trafficRepository, mapStyle: _mapStyle))),
          onImport: _importCatalogue,
          onReference: _openReference,
          onPassageLog: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PassageLogScreen()),
              ),
          onLegend: _showLegend,
          onToggleReference: _toggleReference,
          referenceActive: _alarms.any((a) => a.id.startsWith('mi:')) &&
              _alarms
                  .where((a) => a.id.startsWith('mi:'))
                  .every((a) => a.isActive)),
      body: Builder(
        builder: (context) => Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialPosition,
                initialZoom: _userLocation == null ? 6 : 15,
                onMapReady: () {
                  _mapReady = true;
                  _centerVehicle();
                  if (mounted) setState(() {});
                },
                onPositionChanged: (_, gesture) {
                  if (gesture && _followVehicle) {
                    setState(() => _followVehicle = false);
                  }
                  if (_viewportRefresh?.isActive != true) {
                    _viewportRefresh =
                        Timer(const Duration(milliseconds: 100), () {
                      if (mounted) setState(() {});
                    });
                  }
                },
                initialRotation: 0,
                interactionOptions: InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    cursorKeyboardRotationOptions:
                        CursorKeyboardRotationOptions.disabled(),
                    keyboardOptions:
                        const KeyboardOptions(enableQERotating: false)),
                // Without these flutter_map's zoom clamp is a no-op and a
                // fast pinch can drive the camera to negative infinity; see
                // [mapMinZoom].
                minZoom: mapMinZoom,
                maxZoom: mapMaxZoom,
              ),
              children: [
                widget.tileLayer ?? buildTileLayer(context, style: _mapStyle),
                if (_route != null)
                  PolylineLayer(polylines: [
                    Polyline(
                        points: _route!.points,
                        strokeWidth: 6,
                        color: Colors.blue.shade600,
                        borderColor: Colors.white,
                        borderStrokeWidth: 2)
                  ]),
                CircleLayer(circles: _circles),
                MarkerLayer(markers: _markers),
                Positioned(
                  left: 8,
                  right: 90,
                  bottom: MediaQuery.of(context).padding.bottom + 10,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MapScale(),
                        const SizedBox(height: 6),
                        MapAttribution(style: _mapStyle),
                        const SizedBox(height: 10),
                        _buildSpeed(),
                      ]),
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(context),
                    if (_alarmRinging) _buildRingingBanner(context),
                    if (!_alarmRinging) _buildPermissionWarning(context),
                    const OfflineNotice(),
                  ],
                ),
              ),
            ),
            _buildMapControls(context),
          ],
        ),
      ),
    );
  }

  /// Keep SnackBars near the bottom and controls clear of the vehicle speed.
  /// In landscape a horizontal row leaves room for the route panel above.
  Widget _buildMapControls(BuildContext context) => Positioned(
        right: 12,
        bottom: _mapControlsBottomInset(context),
        child: IgnorePointer(
            ignoring: _mapControlsHidden,
            child: AnimatedOpacity(
                opacity: _mapControlsHidden ? 0 : 1,
                duration: const Duration(milliseconds: 160),
                child: Flex(
                    direction: MediaQuery.sizeOf(context).height < 500
                        ? Axis.horizontal
                        : Axis.vertical,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MapControl(
                          tooltip: 'Zoom avant',
                          icon: Icons.add,
                          onPressed: () => _mapController.move(
                              _mapController.camera.center,
                              (_mapController.camera.zoom + 1)
                                  .clamp(mapMinZoom, mapMaxZoom))),
                      const SizedBox(height: 8, width: 8),
                      MapControl(
                          tooltip: 'Zoom arrière',
                          icon: Icons.remove,
                          onPressed: () => _mapController.move(
                              _mapController.camera.center,
                              (_mapController.camera.zoom - 1)
                                  .clamp(mapMinZoom, mapMaxZoom))),
                      const SizedBox(height: 12, width: 12),
                      MapControl(
                          tooltip: _driving.headingUp
                              ? 'Garder le nord en haut'
                              : 'Direction vers le haut',
                          icon: Icons.explore_outlined,
                          selected: _driving.headingUp,
                          onPressed: () =>
                              _driving.update(heading: !_driving.headingUp)),
                      const SizedBox(height: 12, width: 12),
                      MapControl(
                          tooltip: _followVehicle
                              ? 'Centrer sur ma position'
                              : 'Reprendre le suivi du véhicule',
                          icon: Icons.my_location,
                          selected: _followVehicle,
                          onPressed: _locating
                              ? null
                              : () => _locateUser(recenter: true)),
                      const SizedBox(height: 12, width: 12),
                      MapControl(
                          tooltip: 'Style de carte',
                          icon: Icons.layers_outlined,
                          onPressed: _pickMapStyle),
                    ]))),
      );
  Widget _buildTopBar(BuildContext context) {
    final cue = _buildApproachCue();
    return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MapControl(
              tooltip: 'Menu',
              icon: Icons.menu,
              onPressed: () => Scaffold.of(context).openDrawer()),
          if (_route != null || _calculatingRoute || cue != null) ...[
            const SizedBox(width: 10),
            Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_route != null || _calculatingRoute) _buildRoutePanel(),
              if (cue != null) cue,
            ])),
          ],
        ]));
  }

  Widget? _buildApproachCue() {
    if (_passage['stale'] != false ||
        !const ['entered', 'approaching', 'before25']
            .contains(_passage['stageCode'])) {
      return null;
    }
    final age =
        ((_passage['fixAgeMillis'] as num?)?.toDouble() ?? 99999) / 1000;
    final measured = (_passage['distance'] as num?)?.toDouble();
    if (measured == null || age < 0 || age > 3) return null;
    final distance = measured - (_userSpeed ?? 0) * age;
    final threshold = ((_userSpeed ?? 14) * 15).clamp(100.0, 1000.0);
    if (distance <= 0 || distance > threshold) return null;
    final type = PoiType.fromName(_passage['poiType']);
    return Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Icon(PoiStyle.of(type).icon,
                  color:
                      PoiStyle.readable(type, Theme.of(context).colorScheme)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      '${type.label} · environ ${(distance / 10).round() * 10} m',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis)),
            ])));
  }

  Widget _buildSpeed() {
    final speed = _userFixFresh && _fixAge <= 3000 ? _userSpeed : null;
    final limit = _passage['stale'] == false
        ? (_passage['speedLimitKmh'] as num?)?.toInt()
        : null;
    return DrivingSpeed(
        kmh: speed == null ? null : (speed * 3.6).round(), pointLimit: limit);
  }

  Future<void> _openPlaces() async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(builder: (context, update) {
              _placesRefresh = update;
              return _buildAlarmSheet(context, expanded: true);
            }));
    _placesRefresh = null;
    if (mounted) setState(() => _sheetExtent = _sheetCollapsed);
  }

  Future<void> _startRoute() async {
    if (_calculatingRoute) return;
    final picked = await Navigator.of(context).push<PickedLocation>(
        MaterialPageRoute(
            builder: (_) => LocationPickerScreen(
                initialCenter: _userLocation ?? _initialPosition,
                autofocusSearch: true,
                destinationOnly: true)));
    if (picked == null || !mounted) return;
    _routeDestination = LatLng(picked.latitude, picked.longitude);
    _destinationLabel = picked.label;
    await _calculateRoute();
  }

  Future<void> _calculateRoute() async {
    if (_routeDestination == null || _calculatingRoute) return;
    await _locateUser(recenter: true);
    if (!mounted) return;
    if (!_userFixFresh || _userLocation == null) {
      _notify('Une position récente est nécessaire pour calculer le départ.');
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Calculer l’itinéraire en ligne'),
                content: const Text(
                    'Le départ et la destination seront transmis au serveur de routage FOSSGIS / OpenStreetMap. Le tracé obtenu reste en mémoire pendant cette navigation. Aucune position n’est envoyée à un modèle IA.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Calculer'))
                ]));
    if (confirmed != true || !mounted) return;
    if (!_userFixFresh || _fixAge > 5000) {
      await _locateUser(recenter: true);
      if (!mounted || !_userFixFresh) return;
    }
    final request = ++_routeRequest;
    setState(() => _calculatingRoute = true);
    try {
      final route = await _routeService.calculate(_userLocation!,
          _routeDestination!, _destinationLabel ?? 'Destination');
      if (!mounted || request != _routeRequest) return;
      setState(() {
        _route = route;
        _followVehicle = true;
      });
      _centerVehicle(force: true);
    } catch (_) {
      if (mounted && request == _routeRequest) {
        _notify('Itinéraire indisponible. Vérifier la connexion et réessayer.');
      }
    } finally {
      if (mounted && request == _routeRequest) {
        setState(() => _calculatingRoute = false);
      }
    }
  }

  Widget _buildRoutePanel() {
    final route = _route;
    if (_calculatingRoute) {
      return const LinearProgressIndicator(
          semanticsLabel: 'Calcul de l’itinéraire');
    }
    if (route == null) return const SizedBox.shrink();
    final progress = _userFixFresh && _userLocation != null
        ? route.progress(_userLocation!)
        : null;
    final remaining = progress?.metres ?? route.distance;
    final duration = progress?.seconds ?? route.duration;
    return Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(route.destination,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (progress?.offRoute != true) Text(
                  '${(remaining / 1000).toStringAsFixed(1)} km · ${(duration / 60).ceil()} min estimées'),
              if (!_userFixFresh) const Text('Position à actualiser'),
              if (progress?.offRoute == true)
                TextButton(
                    onPressed: _calculateRoute,
                    child: const Text('Hors itinéraire · recalculer')),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton(
                    tooltip: 'Voir l’ensemble de l’itinéraire',
                    icon: const Icon(Icons.route),
                    onPressed: () {
                      setState(() => _followVehicle = false);
                      _mapController.fitCamera(CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(route.points),
                          padding: const EdgeInsets.all(72)));
                    }),
                IconButton(
                    tooltip: 'Arrêter l’itinéraire',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                          _routeRequest++;
                          _route = null;
                          _routeDestination = null;
                        }))
              ]),
              const Text('Tracé sans guidage vocal · © OpenStreetMap · FOSSGIS',
                  style: TextStyle(fontSize: 10)),
            ])));
  }

  Widget _buildPermissionWarning(BuildContext context) {
    final permissions = _permissions;
    if (permissions == null || permissions.isFullyReady) {
      return const SizedBox.shrink();
    }
    if (!_alarms.any((a) => a.isActive)) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final needsFullScreen =
        _alarms.any((alarm) => alarm.isActive && !alarm.repeatOnEveryEntry);
    final missing = <String>[
      if (!permissions.locationServiceEnabled) 'la localisation du téléphone',
      if (!permissions.foregroundLocationGranted) 'l’accès à la position',
      if (!permissions.backgroundLocationGranted) '« Autoriser tout le temps »',
      if (!permissions.notificationsGranted) 'les notifications',
      if (needsFullScreen && !permissions.fullScreenIntentAllowed)
        'l’alarme en plein écran',
      if (!permissions.batteryOptimizationDisabled)
        'la batterie sans restriction',
    ];
    if (missing.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Des fonctions d’alerte sont limitées',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Manque : ${missing.join(', ')}.',
                  style:
                      TextStyle(color: scheme.onErrorContainer, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ReliabilityScreen(onRepairStore: _repairNativeStore)),
            ),
            child: const Text('Corriger'),
          ),
        ],
      ),
    );
  }

  Widget _buildRingingBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.alarm, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Alerte en cours',
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          FilledButton(onPressed: _stopAlarm, child: const Text('Arrêter')),
        ],
      ),
    );
  }

  Widget _buildAlarmSheet(BuildContext context, {bool expanded = false}) {
    final scheme = Theme.of(context).colorScheme;
    final activeCount = _alarms.where((a) => a.isActive).length;
    final visibleAlarms = _alarms
        .where((alarm) =>
            (_poiFilter == null || alarm.poiType == _poiFilter) &&
            ('${alarm.label} ${alarm.poiType.label} ${alarm.note}'
                .toLowerCase()
                .contains(_poiQuery.toLowerCase())))
        .toList()
      ..sort((a, b) => _userFixFresh
          ? (_distanceTo(a) ?? double.infinity)
              .compareTo(_distanceTo(b) ?? double.infinity)
          : a.label.compareTo(b.label));

    // Listens rather than polls: the notification fires on every drag frame,
    // which is what lets the map controls track the sheet instead of snapping
    // once it settles.
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        if (notification.extent != _sheetExtent) {
          setState(() => _sheetExtent = notification.extent);
        }
        return false;
      },
      child: DraggableScrollableSheet(
        initialChildSize: expanded ? .92 : _sheetCollapsed,
        minChildSize: expanded ? .5 : _sheetCollapsed,
        maxChildSize: expanded ? .96 : _sheetExpanded,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  blurRadius: 16,
                  color: scheme.shadow.withValues(alpha: 0.16),
                ),
              ],
            ),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: scheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        if (_alarms.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Aucun lieu enregistré',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Touche « Ajouter un lieu » pour chercher une '
                                  'destination, puis choisis à quelle distance '
                                  'l’alerte doit sonner.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              children: [
                                Text(
                                  '${_alarms.length} '
                                  '${_alarms.length == 1 ? 'lieu' : 'lieux'}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const Spacer(),
                                if (activeCount > 0)
                                  Text(
                                    '$activeCount armés',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: TextField(
                              onChanged: (query) {
                                setState(() => _poiQuery = query);
                                _placesRefresh?.call(() {});
                              },
                              decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'Filtrer les lieux',
                                  prefixIcon: Icon(Icons.search)),
                            )),
                            PopupMenuButton<String>(
                              tooltip: 'Filtrer par type',
                              icon: const Icon(Icons.filter_list),
                              onSelected: (type) {
                                setState(() => _poiFilter = type == 'all'
                                    ? null
                                    : PoiType.fromName(type));
                                _placesRefresh?.call(() {});
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'all',
                                    child: Text('Tous les types')),
                                ...PoiType.values.map((type) => PopupMenuItem(
                                    value: type.name, child: Text(type.label))),
                              ],
                            )
                          ]),
                          Text(
                              '${visibleAlarms.length} lieux · ${_poiFilter?.label ?? 'Tous les types'} · ${_userFixFresh ? 'les plus proches en premier' : 'ordre alphabétique, GPS à actualiser'}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_alarms.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: ValueListenableBuilder<DistanceUnit>(
                      valueListenable: LocReminderApp.unitOf(context),
                      builder: (context, unit, _) => SliverList.builder(
                        itemCount: visibleAlarms.length,
                        itemBuilder: (context, index) {
                          final alarm = visibleAlarms[index];
                          return AlarmCard(
                            alarm: alarm,
                            distanceMetres: _distanceTo(alarm),
                            unit: unit,
                            onTap: () => _focusAlarm(alarm),
                            onToggle: () async {
                              await _toggleAlarm(alarm);
                              _placesRefresh?.call(() {});
                            },
                            onEdit: () async {
                              await _editAlarm(alarm);
                              _placesRefresh?.call(() {});
                            },
                            onDelete: () async {
                              await _deleteAlarm(alarm);
                              _placesRefresh?.call(() {});
                            },
                          );
                        },
                      ),
                    ),
                  ),
                if (_alarms.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 24),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
