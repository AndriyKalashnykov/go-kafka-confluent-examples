//go:build integration

// Package kafkaroundtrip_test exercises the producer + consumer Run loops
// against a real Kafka broker launched via Testcontainers. The broker runs
// Apache Kafka in KRaft mode (no Zookeeper).
//
// The advertised listener is computed dynamically from whatever host+port
// Testcontainers publishes (which differs between a direct `go test` on the
// host and a `go test` run inside an `act` container that sees Docker over
// the bridge gateway). The override entrypoint waits for a config file with
// KAFKA_ADVERTISED_LISTENERS, sourced before the normal Kafka entrypoint.
//
// The stock testcontainers-go/modules/kafka wrapper (v0.42.0) is hard-coded
// to Confluent's configure scripts and fails with `apache/kafka` images; this
// is the documented workaround.
package kafkaroundtrip_test

import (
	"bytes"
	"context"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/AndriyKalashnykov/go-kafka-confluent-examples/internal/consumer"
	"github.com/AndriyKalashnykov/go-kafka-confluent-examples/internal/producer"
	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

const (
	kafkaImage     = "apache/kafka:3.9.0"
	testTopic      = "test-topic"
	messagesToSend = 5
	consumeTimeout = 60 * time.Second
	clusterID      = "MkU3OEVBNTcwNTJENDM2Qk"
)

func TestProducerConsumerRoundTrip(t *testing.T) {
	ctx := context.Background()

	bootstrap, terminate := startKafka(t, ctx)
	defer terminate()
	t.Logf("Kafka bootstrap: %s", bootstrap)

	createTopic(t, ctx, bootstrap, testTopic)

	producerOut := &syncBuffer{}
	producerCtx, producerCancel := context.WithTimeout(ctx, 90*time.Second)
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

// TestConsumer_CtxCancelExitsCleanly verifies that consumer.Run returns nil
// when its context is cancelled before any message arrives. Pre-cancels the
// ctx, subscribes to a fresh topic with no messages, and asserts Run exits
// within a short deadline. Catches regressions where the loop accidentally
// blocks on ReadMessage instead of checking ctx.Err().
func TestConsumer_CtxCancelExitsCleanly(t *testing.T) {
	ctx := context.Background()

	bootstrap, terminate := startKafka(t, ctx)
	defer terminate()

	const idleTopic = "idle-topic"
	createTopic(t, ctx, bootstrap, idleTopic)

	consumerCtx, consumerCancel := context.WithCancel(ctx)
	consumerCancel() // pre-cancelled — Run should exit on the first ctx.Err() check

	done := make(chan error, 1)
	go func() {
		done <- consumer.Run(consumerCtx, consumer.Config{
			KafkaConfig: kafka.ConfigMap{"bootstrap.servers": bootstrap},
			Topic:       idleTopic,
			GroupID:     "ctx-cancel-test",
			PollTimeout: 50 * time.Millisecond,
		})
	}()

	select {
	case err := <-done:
		if err != nil {
			t.Errorf("Run returned %v on pre-cancelled ctx; want nil", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("Run did not exit within 10s after ctx cancellation")
	}
}

// TestConsumer_MaxMessagesEarlyReturn verifies that Run returns after
// MaxMessages have been consumed even when more messages remain available.
// Produces N+5 events and asks the consumer for N — Run must stop at N
// without continuing to drain the topic.
func TestConsumer_MaxMessagesEarlyReturn(t *testing.T) {
	ctx := context.Background()

	bootstrap, terminate := startKafka(t, ctx)
	defer terminate()

	const cappedTopic = "capped-topic"
	createTopic(t, ctx, bootstrap, cappedTopic)

	const want = 3
	const produced = want + 5
	producerCtx, producerCancel := context.WithTimeout(ctx, 30*time.Second)
	defer producerCancel()
	if err := producer.Run(producerCtx, producer.Config{
		KafkaConfig: kafka.ConfigMap{"bootstrap.servers": bootstrap},
		Topic:       cappedTopic,
		NumMessages: produced,
		Users:       []string{"alice"},
		Items:       []string{"widget"},
		Out:         &syncBuffer{},
	}); err != nil {
		t.Fatalf("producer.Run: %v", err)
	}

	consumerOut := &syncBuffer{}
	consumerCtx, consumerCancel := context.WithTimeout(ctx, consumeTimeout)
	defer consumerCancel()
	if err := consumer.Run(consumerCtx, consumer.Config{
		KafkaConfig: kafka.ConfigMap{"bootstrap.servers": bootstrap},
		Topic:       cappedTopic,
		GroupID:     "max-messages-test",
		MaxMessages: want,
		PollTimeout: 100 * time.Millisecond,
		Out:         consumerOut,
	}); err != nil {
		t.Fatalf("consumer.Run: %v", err)
	}

	got := strings.Count(consumerOut.String(), "Consumed event from topic "+cappedTopic)
	if got != want {
		t.Errorf("consumed %d events, want exactly %d (MaxMessages cap); output:\n%s",
			got, want, consumerOut.String())
	}
}

// startKafka boots an Apache Kafka broker in KRaft mode. The container's
// entrypoint is overridden to block until a /tmp/advertised.env file is
// written with KAFKA_ADVERTISED_LISTENERS pointing to the Testcontainers-
// mapped host:port (computed in the PostStart hook), then exec's the normal
// Kafka entrypoint. This avoids the `localhost:9092` metadata-leak footgun.
func startKafka(t *testing.T, ctx context.Context) (bootstrap string, terminate func()) {
	t.Helper()

	req := testcontainers.ContainerRequest{
		Image:        kafkaImage,
		ExposedPorts: []string{"9092/tcp"},
		Env: map[string]string{
			"KAFKA_NODE_ID":                                  "1",
			"KAFKA_PROCESS_ROLES":                            "broker,controller",
			"KAFKA_CONTROLLER_QUORUM_VOTERS":                 "1@localhost:9093",
			"KAFKA_LISTENERS":                                "PLAINTEXT://:9092,CONTROLLER://:9093",
			"KAFKA_LISTENER_SECURITY_PROTOCOL_MAP":           "PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT",
			"KAFKA_CONTROLLER_LISTENER_NAMES":                "CONTROLLER",
			"KAFKA_INTER_BROKER_LISTENER_NAME":               "PLAINTEXT",
			"KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR":         "1",
			"KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR": "1",
			"KAFKA_TRANSACTION_STATE_LOG_MIN_ISR":            "1",
			"KAFKA_LOG_DIRS":                                 "/tmp/kraft-combined-logs",
			"CLUSTER_ID":                                     clusterID,
		},
		Entrypoint: []string{"/bin/sh", "-c", "while [ ! -f /tmp/advertised.env ]; do sleep 0.05; done; . /tmp/advertised.env; exec /etc/kafka/docker/run"},
		WaitingFor: wait.ForLog("Kafka Server started").WithStartupTimeout(120 * time.Second),
		LifecycleHooks: []testcontainers.ContainerLifecycleHooks{
			{
				PostStarts: []testcontainers.ContainerHook{
					func(ctx context.Context, c testcontainers.Container) error {
						mapped, err := c.MappedPort(ctx, "9092/tcp")
						if err != nil {
							return fmt.Errorf("mapped port: %w", err)
						}
						host, err := c.Host(ctx)
						if err != nil {
							return fmt.Errorf("host: %w", err)
						}
						content := fmt.Sprintf("export KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://%s:%s\n", host, mapped.Port())
						return c.CopyToContainer(ctx, []byte(content), "/tmp/advertised.env", 0o644)
					},
				},
			},
		},
	}

	c, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: req,
		Started:          true,
	})
	if err != nil {
		t.Fatalf("start Kafka container: %v", err)
	}
	terminate = func() {
		if err := c.Terminate(ctx); err != nil {
			t.Logf("terminate container: %v", err)
		}
	}

	mapped, err := c.MappedPort(ctx, "9092/tcp")
	if err != nil {
		terminate()
		t.Fatalf("mapped port: %v", err)
	}
	host, err := c.Host(ctx)
	if err != nil {
		terminate()
		t.Fatalf("host: %v", err)
	}
	return fmt.Sprintf("%s:%s", host, mapped.Port()), terminate
}

// createTopic creates testTopic via the AdminClient so the producer's first
// Produce call sees a ready topic instead of retrying "Unknown topic".
func createTopic(t *testing.T, ctx context.Context, bootstrap, topic string) {
	t.Helper()
	admin, err := kafka.NewAdminClient(&kafka.ConfigMap{"bootstrap.servers": bootstrap})
	if err != nil {
		t.Fatalf("admin client: %v", err)
	}
	defer admin.Close()

	createCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	results, err := admin.CreateTopics(createCtx, []kafka.TopicSpecification{{
		Topic:             topic,
		NumPartitions:     1,
		ReplicationFactor: 1,
	}})
	if err != nil {
		t.Fatalf("CreateTopics: %v", err)
	}
	for _, r := range results {
		if r.Error.Code() != kafka.ErrNoError && r.Error.Code() != kafka.ErrTopicAlreadyExists {
			t.Fatalf("CreateTopic %s: %v", r.Topic, r.Error)
		}
	}
}

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
