import 'package:flutter_test/flutter_test.dart';
import 'package:instapharm/models/map_style.dart';
import 'package:instapharm/providers/preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  test('MapDetailOptions : trafic désactivé par défaut', () {
    const opts = MapDetailOptions();
    expect(opts.traffic, isFalse);
    expect(opts.transit, isFalse);
    expect(opts.copyWith(traffic: true).traffic, isTrue);
  });

  test('rayon de recherche par défaut à 3 km', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(searchRadiusKmProvider), 3.0);
  });
}
