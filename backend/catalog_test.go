package main

import "testing"

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
	if groups != 2 {
		t.Fatalf("chip groups = %d, want 2", groups)
	}
	if chipCount != len(catalogSituations) {
		t.Fatalf("chips = %d, want %d", chipCount, len(catalogSituations))
	}
}
