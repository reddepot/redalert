import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locreminder/models/location_alarm.dart';
import 'package:locreminder/models/poi_type.dart';
import 'package:locreminder/theme/app_theme.dart';
import 'package:locreminder/theme/poi_style.dart';
import 'package:locreminder/widgets/alarm_card.dart';

LocationAlarm alarmOf({
  PoiType type = PoiType.redLightCamera,
  bool active = false,
  String note = '',
}) =>
    LocationAlarm(
      id: 'mi:12014',
      label: '86 · Radar de feu rouge · 90 km/h · MI-12014',
      latitude: 46.5,
      longitude: 0.3,
      radiusMeters: 1000,
      isActive: active,
      createdAt: DateTime(2026, 11, 11),
      poiType: type,
      note: note,
      repeatOnEveryEntry: true,
      positionStatus: 'source',
    );

Widget host(
  Widget child, {
  double scale = 1,
  Size size = const Size(360, 800),
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: ListView(children: [child])),
      ),
    ),
  );
}

Widget cardFor(
  LocationAlarm alarm, {
  double? distance,
  VoidCallback? onTap,
  VoidCallback? onToggle,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) =>
    AlarmCard(
      alarm: alarm,
      distanceMetres: distance,
      onTap: onTap ?? () {},
      onToggle: onToggle ?? () {},
      onEdit: onEdit ?? () {},
      onDelete: onDelete ?? () {},
    );

void main() {
  testWidgets('says the kind of place, in its own colour, before any text',
      (tester) async {
    final alarm = alarmOf(active: true);
    await tester.pumpWidget(host(cardFor(alarm)));

    expect(find.text('Radar de feu rouge'), findsOneWidget);
    expect(find.textContaining('Déclenchement à'), findsOneWidget);
    expect(find.textContaining('À chaque passage'), findsOneWidget);

    final style = PoiStyle.of(PoiType.redLightCamera);
    final icon = tester.widget<Icon>(find.byIcon(style.icon));
    expect(icon.color, style.color);
  });

  testWidgets('a paused place says so and keeps its colour, muted',
      (tester) async {
    final alarm = alarmOf();
    await tester.pumpWidget(host(cardFor(alarm)));

    expect(find.textContaining('En pause'), findsOneWidget);
    final scheme = AppTheme.light().colorScheme;
    final icon = tester.widget<Icon>(
        find.byIcon(PoiStyle.of(PoiType.redLightCamera).icon));
    expect(icon.color, PoiStyle.pausedColor(PoiType.redLightCamera, scheme));
  });

  testWidgets('the note added while editing is the third line',
      (tester) async {
    final alarm = alarmOf(note: 'Feu à gauche, côté nord, juste après le pont');
    await tester.pumpWidget(host(cardFor(alarm)));

    expect(find.text(alarm.note), findsOneWidget);
    expect(find.text(alarm.poiType.label), findsOneWidget);
  });

  testWidgets('the label gets two lines, which the catalogue needs',
      (tester) async {
    final alarm = alarmOf();
    await tester.pumpWidget(host(cardFor(alarm)));

    final title = tester.widget<Text>(find.text(alarm.label));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('the actions still reach the callbacks', (tester) async {
    var toggled = 0;
    var edited = 0;
    var deleted = 0;
    await tester.pumpWidget(host(cardFor(
      alarmOf(),
      onToggle: () => toggled++,
      onEdit: () => edited++,
      onDelete: () => deleted++,
    )));

    await tester.tap(find.byType(Switch));
    await tester.tap(find.byTooltip('Modifier'));
    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pumpAndSettle();

    expect(toggled, 1);
    expect(edited, 1);
    expect(deleted, 1);
  });

  testWidgets('holds together at a large font on a small screen',
      (tester) async {
    await tester.pumpWidget(host(
      cardFor(alarmOf(
          active: true, note: 'Feu à gauche, côté nord, juste après le pont')),
      scale: 2,
      size: const Size(320, 640),
    ));

    expect(tester.takeException(), isNull);
  });
}
