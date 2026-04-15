package producer

import (
	"bytes"
	"context"
	"strings"
	"testing"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
)

func TestRun_MissingTopicReturnsError(t *testing.T) {
	err := Run(context.Background(), Config{})
	if err == nil || !strings.Contains(err.Error(), "Topic is required") {
		t.Fatalf("Run({}) error = %v, want error containing %q", err, "Topic is required")
	}
}

func TestHandleEvent(t *testing.T) {
	topic := "t"
	deliveredPartition := kafka.TopicPartition{Topic: &topic, Partition: 0}
	failedPartition := kafka.TopicPartition{Topic: &topic, Partition: 0, Error: kafka.NewError(kafka.ErrMsgTimedOut, "timeout", false)}

	tests := []struct {
		name       string
		event      kafka.Event
		wantSubstr string
	}{
		{"delivered", &kafka.Message{TopicPartition: deliveredPartition, Key: []byte("k"), Value: []byte("v")}, "Produced event to topic t"},
		{"delivery failed", &kafka.Message{TopicPartition: failedPartition}, "Failed to deliver message"},
		{"kafka error", kafka.NewError(kafka.ErrAllBrokersDown, "down", false), "Error:"},
		{"unknown event", kafka.PartitionEOF(deliveredPartition), "Ignored event"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var buf bytes.Buffer
			handleEvent(&buf, tt.event)
			if !strings.Contains(buf.String(), tt.wantSubstr) {
				t.Errorf("handleEvent output %q, want substring %q", buf.String(), tt.wantSubstr)
			}
		})
	}
}
