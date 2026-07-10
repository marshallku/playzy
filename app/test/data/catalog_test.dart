import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/core/providers.dart';
import 'package:playzy/data/catalog/catalog_api.dart';
import 'package:playzy/domain/situation.dart';
import 'package:playzy/sdui/sdui_models.dart';

class _NewerSchemaCatalog implements CatalogApi {
  @override
  Future<SduiDocument> fetchSituationCatalog() async =>
      const SduiDocument(schemaVersion: 999, components: [SduiSection(title: 'nope')]);
}

class _ThrowingCatalog implements CatalogApi {
  @override
  Future<SduiDocument> fetchSituationCatalog() async => throw Exception('offline');
}

/// Supported schema but no usable chips (empty group + only a section).
class _EmptyCatalog implements CatalogApi {
  @override
  Future<SduiDocument> fetchSituationCatalog() async => const SduiDocument(
        schemaVersion: 1,
        components: [SduiSection(title: '텅 빔'), SduiChipGroup(chips: [])],
      );
}

void main() {
  group('bundledSituationCatalog', () {
    test('mirrors the default situations across two chip groups', () {
      final doc = bundledSituationCatalog();
      final chips = doc.components.whereType<SduiChipGroup>().expand((g) => g.chips);
      final ids = chips.map((c) => c.id).toSet();

      expect(doc.components.whereType<SduiSection>(), hasLength(2));
      expect(doc.components.whereType<SduiChipGroup>(), hasLength(2));
      expect(ids, kDefaultSituations.map((s) => s.id).toSet());
    });

    test('FakeCatalogApi returns the bundled catalog', () async {
      final doc = await const FakeCatalogApi().fetchSituationCatalog();
      expect(doc.schemaVersion, SduiDocument.supportedVersion);
      expect(doc.components, isNotEmpty);
    });
  });

  group('situationCatalogProvider fallback', () {
    Future<SduiDocument> read(CatalogApi api) async {
      final c = ProviderContainer(overrides: [catalogApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      return c.read(situationCatalogProvider.future);
    }

    test('falls back to bundled when the document is a newer schema', () async {
      final doc = await read(_NewerSchemaCatalog());
      expect(doc.schemaVersion, SduiDocument.supportedVersion);
      expect(doc.components.whereType<SduiChipGroup>(), isNotEmpty);
    });

    test('falls back to bundled when the fetch throws', () async {
      final doc = await read(_ThrowingCatalog());
      expect(doc.components.whereType<SduiChipGroup>(), isNotEmpty);
    });

    test('falls back to bundled when the document has no usable chips', () async {
      final doc = await read(_EmptyCatalog());
      final chips = doc.components.whereType<SduiChipGroup>().expand((g) => g.chips);
      expect(chips, isNotEmpty);
    });
  });
}
