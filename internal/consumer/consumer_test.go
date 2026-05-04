package consumer

import (
	"context"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
)

func TestRun_MissingTopicReturnsError(t *testing.T) {
	err := Run(context.Background(), Config{})
	if err == nil || !strings.Contains(err.Error(), "Topic is required") {
		t.Fatalf("Run({}) error = %v, want error containing %q", err, "Topic is required")
	}
}

func TestApplyDefaults(t *testing.T) {
	tests := []struct {
		name string
		in   Config
		want Config
	}{
		{
			name: "all zero — fills every default",
			in:   Config{KafkaConfig: kafka.ConfigMap{}},
			want: Config{
				KafkaConfig:     kafka.ConfigMap{},
				GroupID:         "kafka-go-getting-started",
				AutoOffsetReset: "earliest",
				PollTimeout:     100 * time.Millisecond,
				Out:             io.Discard,
			},
		},
		{
			name: "explicit field overrides default",
			in: Config{
				KafkaConfig:     kafka.ConfigMap{},
				GroupID:         "my-group",
				AutoOffsetReset: "latest",
				PollTimeout:     500 * time.Millisecond,
			},
			want: Config{
				KafkaConfig:     kafka.ConfigMap{},
				GroupID:         "my-group",
				AutoOffsetReset: "latest",
				PollTimeout:     500 * time.Millisecond,
				Out:             io.Discard,
			},
		},
		{
			name: "KafkaConfig already has group.id — defaulting skipped",
			in: Config{
				KafkaConfig: kafka.ConfigMap{"group.id": "from-map"},
			},
			want: Config{
				KafkaConfig:     kafka.ConfigMap{"group.id": "from-map"},
				GroupID:         "", // stays empty so Run won't overwrite the map entry
				AutoOffsetReset: "earliest",
				PollTimeout:     100 * time.Millisecond,
				Out:             io.Discard,
			},
		},
		{
			name: "KafkaConfig already has auto.offset.reset — defaulting skipped",
			in: Config{
				KafkaConfig: kafka.ConfigMap{"auto.offset.reset": "latest"},
			},
			want: Config{
				KafkaConfig:     kafka.ConfigMap{"auto.offset.reset": "latest"},
				GroupID:         "kafka-go-getting-started",
				AutoOffsetReset: "",
				PollTimeout:     100 * time.Millisecond,
				Out:             io.Discard,
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.in
			applyDefaults(&got)
			if got.GroupID != tt.want.GroupID {
				t.Errorf("GroupID = %q, want %q", got.GroupID, tt.want.GroupID)
			}
			if got.AutoOffsetReset != tt.want.AutoOffsetReset {
				t.Errorf("AutoOffsetReset = %q, want %q", got.AutoOffsetReset, tt.want.AutoOffsetReset)
			}
			if got.PollTimeout != tt.want.PollTimeout {
				t.Errorf("PollTimeout = %v, want %v", got.PollTimeout, tt.want.PollTimeout)
			}
			if got.Out == nil {
				t.Error("Out is nil; want io.Discard")
			}
		})
	}
}

// TestRun_BrokerUnreachable_ExitsOnCtxCancel verifies Run respects ctx
// cancellation when the broker is unreachable, instead of blocking forever
// in ReadMessage. Uses a closed port (127.0.0.1:1) — librdkafka's lazy
// connection model means kafka.NewConsumer succeeds; the failures appear
// as transient errors from ReadMessage which Run silently retries.
func TestRun_BrokerUnreachable_ExitsOnCtxCancel(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	done := make(chan error, 1)
	go func() {
		done <- Run(ctx, Config{
			KafkaConfig: kafka.ConfigMap{"bootstrap.servers": "127.0.0.1:1"},
			Topic:       "unreachable-topic",
			GroupID:     "test",
			PollTimeout: 50 * time.Millisecond,
		})
	}()

	select {
	case err := <-done:
		if err != nil {
			t.Errorf("Run returned %v on ctx-cancel; want nil", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not exit within 5s after ctx cancellation")
	}
}
