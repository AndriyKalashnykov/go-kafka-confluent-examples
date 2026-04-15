//go:build integration

// Package kafkaroundtrip_test exercises the producer + consumer Run loops
// against a real Kafka broker launched via Testcontainers (KRaft mode — no
// Zookeeper). Requires Docker to be available on the host.
//
// NOTE: the testcontainers-go/kafka module's `confluentinc/confluent-local`
// setup re-writes `KAFKA_ADVERTISED_LISTENERS` at container start, but the
// rewrite doesn't propagate reliably on every Docker host (observed: broker
// advertises `localhost:9092` internally, clients can't route). The test is
// therefore gated on the `RUN_KAFKA_INTEGRATION=1` environment variable so it
// only runs on hosts where the setup has been verified. See CLAUDE.md
// Upgrade Backlog for the follow-up to switch to a `GenericContainer` with
// hand-written `KAFKA_ADVERTISED_LISTENERS` patching.
package kafkaroundtrip_test

import (
	"bytes"
	"context"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/AndriyKalashnykov/go-kafka-confluent-examples/internal/consumer"
	"github.com/AndriyKalashnykov/go-kafka-confluent-examples/internal/producer"
	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
	kafkatc "github.com/testcontainers/testcontainers-go/modules/kafka"
)

const (
	// confluent-local ships the full Confluent broker in KRaft mode; the
	// testcontainers/kafka module is hard-coded to drive Confluent-platform
	// images, so `apache/kafka` doesn't work here.
	kafkaImage     = "confluentinc/confluent-local:7.8.0"
	testTopic      = "test-topic"
	messagesToSend = 5
	consumeTimeout = 45 * time.Second
)

func TestProducerConsumerRoundTrip(t *testing.T) {
	if os.Getenv("RUN_KAFKA_INTEGRATION") != "1" {
		t.Skip("skipping Kafka integration test: set RUN_KAFKA_INTEGRATION=1 to run (requires Docker and a verified testcontainers-kafka setup)")
	}
	ctx := context.Background()

	kc, err := kafkatc.Run(ctx, kafkaImage, kafkatc.WithClusterID("test-cluster"))
	if err != nil {
		t.Fatalf("start Kafka container: %v", err)
	}
	t.Cleanup(func() {
		if err := kc.Terminate(ctx); err != nil {
			t.Logf("terminate container: %v", err)
		}
	})

	brokers, err := kc.Brokers(ctx)
	if err != nil {
		t.Fatalf("get brokers: %v", err)
	}
	if len(brokers) == 0 {
		t.Fatal("no brokers returned by container")
	}
	bootstrap := strings.Join(brokers, ",")
	t.Logf("Kafka bootstrap: %s", bootstrap)

	// Produce first, then consume with auto.offset.reset=earliest. Ordering
	// the two phases avoids races between consumer-group-join and the first
	// produce call, and keeps the test independent of poll timing.
	producerOut := &syncBuffer{}
	producerCtx, producerCancel := context.WithTimeout(ctx, 30*time.Second)
	defer producerCancel()
	if err := producer.Run(producerCtx, producer.Config{
		KafkaConfig: kafka.ConfigMap{
			"bootstrap.servers": bootstrap,
		},
		Topic:       testTopic,
		NumMessages: messagesToSend,
		Users:       []string{"alice", "bob", "carol", "dave", "eve"},
		Items:       []string{"widget"},
		Out:         producerOut,
	}); err != nil {
		t.Fatalf("producer.Run: %v", err)
	}
	t.Logf("producer output:\n%s", producerOut.String())

	consumerOut := &syncBuffer{}
	consumerCtx, consumerCancel := context.WithTimeout(ctx, consumeTimeout)
	defer consumerCancel()
	if err := consumer.Run(consumerCtx, consumer.Config{
		KafkaConfig: kafka.ConfigMap{
			"bootstrap.servers": bootstrap,
		},
		Topic:       testTopic,
		GroupID:     "roundtrip-test",
		MaxMessages: messagesToSend,
		PollTimeout: 100 * time.Millisecond,
		Out:         consumerOut,
	}); err != nil {
		t.Fatalf("consumer.Run: %v", err)
	}

	consumed := consumerOut.String()
	if !strings.Contains(consumed, "Reading topic "+testTopic) {
		t.Errorf("consumer did not log subscription; output:\n%s", consumed)
	}
	if got := strings.Count(consumed, "Consumed event from topic "+testTopic); got != messagesToSend {
		t.Errorf("consumed %d events, want %d; output:\n%s", got, messagesToSend, consumed)
	}

	produced := producerOut.String()
	if got := strings.Count(produced, "Produced event to topic "+testTopic); got != messagesToSend {
		t.Errorf("producer delivery reports: got %d, want %d; output:\n%s",
			got, messagesToSend, produced)
	}
}

// syncBuffer is an io.Writer safe for concurrent use from the consumer's
// delivery-report goroutine and the main test goroutine.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (s *syncBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.buf.Write(p)
}

func (s *syncBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.buf.String()
}
