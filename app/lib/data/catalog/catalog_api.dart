import '../../domain/situation.dart';
import '../../sdui/sdui_models.dart';

/// Fetches the situation-picker catalog as an SDUI document (ADR 0003). The
/// backend can grow/reorder the catalog without an app release; a bundled
/// default backs offline use.
abstract interface class CatalogApi {
  Future<SduiDocument> fetchSituationCatalog();
}

/// Offline/dev implementation — returns the [bundledSituationCatalog].
class FakeCatalogApi implements CatalogApi {
  const FakeCatalogApi();

  @override
  Future<SduiDocument> fetchSituationCatalog() async => bundledSituationCatalog();
}

/// The bundled default catalog, built from [kDefaultSituations]. Used offline
/// and as the fallback when a fetched document can't be rendered — so a parent
/// is never stuck with an empty picker (ADR 0003).
SduiDocument bundledSituationCatalog() {
  SduiChip toChip(Situation s) => SduiChip(id: s.id, label: s.label, emoji: s.emoji);
  List<SduiChip> of(SituationKind kind) =>
      kDefaultSituations.where((s) => s.kind == kind).map(toChip).toList();

  return SduiDocument(
    schemaVersion: SduiDocument.supportedVersion,
    components: [
      const SduiSection(title: '요즘 이런 상황이 있나요?'),
      SduiChipGroup(chips: of(SituationKind.parenting)),
      const SduiSection(title: '이야기에 담고 싶은 마음'),
      SduiChipGroup(chips: of(SituationKind.value)),
      const SduiSection(title: '어떤 모험을 떠날까요?'),
      SduiChipGroup(chips: of(SituationKind.theme)),
    ],
  );
}
