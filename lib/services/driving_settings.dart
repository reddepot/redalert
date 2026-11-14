import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DrivingSettings extends ChangeNotifier {
  static final instance = DrivingSettings();
  bool headingUp = true;
  bool keepScreenAwake = true;
  bool autoFollow = true;
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    headingUp = p.getBool('driving_heading_up') ?? true;
    keepScreenAwake = p.getBool('driving_keep_awake') ?? true;
    autoFollow = p.getBool('driving_auto_follow') ?? true;
    notifyListeners();
  }

  Future<void> update({bool? heading, bool? awake, bool? follow}) async {
    final p = await SharedPreferences.getInstance();
    if (heading != null) {
      await p.setBool('driving_heading_up', heading);
      headingUp = heading;
    }
    if (awake != null) {
      await p.setBool('driving_keep_awake', awake);
      keepScreenAwake = awake;
    }
    if (follow != null) {
      await p.setBool('driving_auto_follow', follow);
      autoFollow = follow;
    }
    notifyListeners();
  }
}
