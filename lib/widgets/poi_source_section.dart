import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/poi_provenance.dart';

class PoiSourceSection extends StatelessWidget {
  const PoiSourceSection({super.key, required this.source});
  final PoiProvenance source;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.source_outlined,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Source du point',
                      style: Theme.of(context).textTheme.titleMedium))
            ]),
            const SizedBox(height: 10),
            Text(source.provider == 'Ministere_interieur'
                ? 'Ministère de l’Intérieur'
                : source.provider),
            Text(
                '${source.provider == 'SNCF Réseau' ? 'Jeu traité le' : 'Extrait daté du'} ${source.dateLabel}'),
            Text('Référence : ${source.recordId}'),
            if (source.classification != null) Text(source.classification!),
            if (source.railwayClass != null &&
                PoiProvenance.railwayClassDescription(source.railwayClass!) !=
                    null)
              Text(
                  PoiProvenance.railwayClassDescription(source.railwayClass!)!),
            if (source.provider == 'SNCF Réseau' &&
                source.lowClearanceDifficult == null)
              const Text(
                  'Difficulté pour véhicules surbaissés : non renseignée.'),
            if (source.rawType != null) Text('Type source : ${source.rawType}'),
            if (source.lowClearanceDifficult == true)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                      'Franchissement signalé difficile pour les véhicules surbaissés.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600))),
            const SizedBox(height: 6),
            const Text(
                'La date du jeu ne garantit pas une vérification récente de chaque lieu.'),
            TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Voir la fiche source'),
                onPressed: () async {
                  var opened = false;
                  try {
                    opened = await launchUrl(Uri.parse(source.url),
                        mode: LaunchMode.externalApplication);
                  } catch (_) {
                    /* Keep the saved place intact when no browser is available. */
                  }
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Impossible d’ouvrir la source.')));
                  }
                }),
          ])));
}
