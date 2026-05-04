package producer

import (
	"bytes"
	"context"
	"errors"
	"io"
	"reflect"
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
			in:   Config{},
			want: Config{
				NumMessages: 10,
				Users:       defaultUsers,
				Items:       defaultItems,
				Out:         io.Discard,
			},
		},
		{
			name: "explicit fields preserved",
			in: Config{
				NumMessages: 3,
				Users:       []string{"alice"},
				Items:       []string{"thing"},
			},
			want: Config{
				NumMessages: 3,
				Users:       []string{"alice"},
				Items:       []string{"thing"},
				Out:         io.Discard,
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.in
			applyDefaults(&got)
			if got.NumMessages != tt.want.NumMessages {
				t.Errorf("NumMessages = %d, want %d", got.NumMessages, tt.want.NumMessages)
			}
			if !reflect.DeepEqual(got.Users, tt.want.Users) {
				t.Errorf("Users = %v, want %v", got.Users, tt.want.Users)
			}
			if !reflect.DeepEqual(got.Items, tt.want.Items) {
				t.Errorf("Items = %v, want %v", got.Items, tt.want.Items)
			}
			if got.Out == nil {
				t.Error("Out is nil; want io.Discard")
			}
		})
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

// fakeProducer is a produceFlusher used to drive produceWithRetry through
// branches that a real broker can't reliably trigger (specifically
// ErrQueueFull, which librdkafka only emits under sustained backpressure
// against a slow broker — not realistic in tests).
type fakeProducer struct {
	produceErrs   []error // errors to return from successive Produce calls
	produceCalls  int
	flushReturns  []int // values to return from successive Flush calls
	flushCalls    int
	deliveredMsgs []*kafka.Message
}

func (f *fakeProducer) Produce(msg *kafka.Message, _ chan kafka.Event) error {
	defer func() { f.produceCalls++ }()
	if f.produceCalls < len(f.produceErrs) {
		return f.produceErrs[f.produceCalls]
	}
	f.deliveredMsgs = append(f.deliveredMsgs, msg)
	return nil
}

func (f *fakeProducer) Flush(_ int) int {
	defer func() { f.flushCalls++ }()
	if f.flushCalls < len(f.flushReturns) {
		return f.flushReturns[f.flushCalls]
	}
	return 0
}

func TestProduceWithRetry(t *testing.T) {
	topic := "t"
	msg := &kafka.Message{
		TopicPartition: kafka.TopicPartition{Topic: &topic, Partition: kafka.PartitionAny},
		Key:            []byte("k"),
		Value:          []byte("v"),
	}

	t.Run("ErrQueueFull → flush + signal retry", func(t *testing.T) {
		fp := &fakeProducer{
			produceErrs: []error{kafka.NewError(kafka.ErrQueueFull, "queue full", false)},
		}
		var buf bytes.Buffer
		err := produceWithRetry(fp, msg, &buf)
		if !errors.Is(err, errQueueFullRetry) {
			t.Fatalf("err = %v, want errQueueFullRetry", err)
		}
		if fp.flushCalls != 1 {
			t.Errorf("flushCalls = %d, want 1", fp.flushCalls)
		}
		if !strings.Contains(buf.String(), "queue full; flushing and retrying") {
			t.Errorf("missing retry log line; got %q", buf.String())
		}
	})

	t.Run("Other Produce error is logged and swallowed", func(t *testing.T) {
		fp := &fakeProducer{
			produceErrs: []error{kafka.NewError(kafka.ErrUnknownTopic, "no topic", false)},
		}
		var buf bytes.Buffer
		err := produceWithRetry(fp, msg, &buf)
		if err != nil {
			t.Errorf("err = %v, want nil (best-effort swallow)", err)
		}
		if fp.flushCalls != 0 {
			t.Errorf("flushCalls = %d, want 0 (Flush only on ErrQueueFull)", fp.flushCalls)
		}
		if !strings.Contains(buf.String(), "Failed to produce message") {
			t.Errorf("missing failure log line; got %q", buf.String())
		}
	})

	t.Run("Successful Produce returns nil with no flush", func(t *testing.T) {
		fp := &fakeProducer{}
		var buf bytes.Buffer
		err := produceWithRetry(fp, msg, &buf)
		if err != nil {
			t.Errorf("err = %v, want nil", err)
		}
		if fp.produceCalls != 1 {
			t.Errorf("produceCalls = %d, want 1", fp.produceCalls)
		}
		if fp.flushCalls != 0 {
			t.Errorf("flushCalls = %d, want 0 on happy path", fp.flushCalls)
		}
	})
}

// TestRun_BrokerUnreachable_ExitsOnCtxCancel verifies Run honors ctx
// cancellation when the broker can't be reached. librdkafka's lazy
// connection model means kafka.NewProducer succeeds; the Produce calls
// queue locally, Flush eventually times out per iteration, and the loop
// continues. ctx-cancel is the only termination signal in this scenario.
func TestRun_BrokerUnreachable_ExitsOnCtxCancel(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	done := make(chan error, 1)
	go func() {
		done <- Run(ctx, Config{
			KafkaConfig: kafka.ConfigMap{"bootstrap.servers": "127.0.0.1:1"},
			Topic:       "unreachable-topic",
			NumMessages: 2,
		})
	}()

	select {
	case err := <-done:
		if err != nil {
			t.Errorf("Run returned %v on ctx-cancel; want nil", err)
		}
	case <-time.After(15 * time.Second):
		t.Fatal("Run did not exit within 15s after ctx cancellation")
	}
}
