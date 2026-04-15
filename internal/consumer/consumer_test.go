package consumer

import (
	"context"
	"strings"
	"testing"
)

func TestRun_MissingTopicReturnsError(t *testing.T) {
	err := Run(context.Background(), Config{})
	if err == nil || !strings.Contains(err.Error(), "Topic is required") {
		t.Fatalf("Run({}) error = %v, want error containing %q", err, "Topic is required")
	}
}
