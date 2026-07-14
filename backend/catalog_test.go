package main

import (
	"os"
	"reflect"
	"regexp"
	"testing"
)

// TestCatalog_MirrorsAppSource is the real parity lock (WU3): it parses the app's
// kDefaultSituations straight out of the Dart source and asserts the backend
// catalogSituations matches it exactly — same ids, labels, kinds, emoji, and
// order. Spot-checks can't catch a one-off label/kind typo between the two
// hand-maintained lists; this does. If the Dart file's entry format changes, this
// fails loudly (which is the point — it forces the two to be reconciled).
func TestCatalog_MirrorsAppSource(t *testing.T) {
	const dartPath = "../app/lib/domain/situation.dart"
	src, err := os.ReadFile(dartPath)
	if err != nil {
		t.Fatalf("read app catalog source %s: %v", dartPath, err)
	}
	// Matches: Situation(id: 'x', label: 'y', kind: SituationKind.z, emoji: 'e'),
	re := regexp.MustCompile(`Situation\(id: '([^']+)', label: '([^']+)', kind: SituationKind\.(\w+), emoji: '([^']+)'\)`)
	matches := re.FindAllStringSubmatch(string(src), -1)
	if len(matches) == 0 {
		t.Fatalf("no Situation entries parsed from %s (format changed?)", dartPath)
	}
	appCatalog := make([]situation, len(matches))
	for i, m := range matches {
		appCatalog[i] = situation{ID: m[1], Label: m[2], Kind: m[3], Emoji: m[4]}
	}
	if !reflect.DeepEqual(appCatalog, catalogSituations) {
		t.Fatalf("app↔backend catalog drift.\n app (%d): %v\n backend (%d): %v",
			len(appCatalog), appCatalog, len(catalogSituations), catalogSituations)
	}
}

func TestSituationLabels(t *testing.T) {
	labels := situationLabels()
	if labels["bedtime"] != "잠자기" {
		t.Fatalf("bedtime label = %q", labels["bedtime"])
	}
	if len(labels) != len(catalogSituations) {
		t.Fatalf("label count = %d", len(labels))
	}
}

func TestSituationCatalogSDUI_Shape(t *testing.T) {
	doc := situationCatalogSDUI()
	if doc["schemaVersion"] != 1 {
		t.Fatalf("schemaVersion = %v", doc["schemaVersion"])
	}
	components, ok := doc["components"].([]map[string]any)
	if !ok {
		t.Fatal("components missing")
	}
	groups := 0
	chipCount := 0
	for _, c := range components {
		if c["type"] == "chip_group" {
			groups++
			chips := c["chips"].([]map[string]any)
			chipCount += len(chips)
		}
	}
	if groups != 3 {
		t.Fatalf("chip groups = %d, want 3 (상황·마음·테마)", groups)
	}
	if chipCount != len(catalogSituations) {
		t.Fatalf("chips = %d, want %d", chipCount, len(catalogSituations))
	}
}

func TestSituationKinds_RoutesValues(t *testing.T) {
	kinds := situationKinds()
	if kinds["courage"] != "value" {
		t.Fatalf("courage kind = %q, want value", kinds["courage"])
	}
	if kinds["bedtime"] != "parenting" {
		t.Fatalf("bedtime kind = %q, want parenting", kinds["bedtime"])
	}
	if kinds["space"] != "theme" {
		t.Fatalf("space kind = %q, want theme", kinds["space"])
	}
	if len(kinds) != len(catalogSituations) {
		t.Fatalf("kind count = %d", len(kinds))
	}
}
