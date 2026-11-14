import 'package:flutter/material.dart';
import '../services/driving_settings.dart';

class DrivingSettingsScreen extends StatelessWidget {
  const DrivingSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final settings = DrivingSettings.instance;
    return Scaffold(
        appBar: AppBar(title: const Text('Carte et conduite')),
        body: ListenableBuilder(
            listenable: settings,
            builder: (context, _) => ListView(children: [
                  SwitchListTile(
                      title: const Text('Suivre le véhicule'),
                      subtitle: const Text(
                          'Garde la position au centre. Déplacer la carte suspend le suivi ; le bouton de centrage le reprend.'),
                      value: settings.autoFollow,
                      onChanged: (v) => settings.update(follow: v)),
                  SwitchListTile(
                      title: const Text('Direction vers le haut'),
                      subtitle: const Text(
                          'La carte suit le cap en déplacement. Désactiver pour garder le nord en haut.'),
                      value: settings.headingUp,
                      onChanged: (v) => settings.update(heading: v)),
                  SwitchListTile(
                      title: const Text('Garder l’écran allumé sur la carte'),
                      subtitle: const Text(
                          'Désactiver pour laisser la veille normale. Les alertes natives continuent indépendamment de l’écran.'),
                      value: settings.keepScreenAwake,
                      onChanged: (v) => settings.update(awake: v)),
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'La vitesse est une estimation de position, pas une mesure du radar. Une limitation affichée appartient au point sélectionné ; une valeur inconnue reste inconnue.')),
                ])));
  }
}
