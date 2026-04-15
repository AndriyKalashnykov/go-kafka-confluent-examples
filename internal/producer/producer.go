// Package producer drives a Confluent Kafka producer from a supplied config.
//
// The core loop is exposed as Run(ctx, cfg) so it can be exercised against a
// real broker in integration tests (see Testcontainers-based tests) without
// pulling in os.Exit, signal handling, or env-var plumbing.
package producer

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math/rand"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
)

var (
	defaultUsers = []string{"eabara", "jsmith", "sgarcia", "jbernard", "htanaka", "awalther"}
	defaultItems = []string{"book", "alarm clock", "t-shirts", "gift card", "batteries"}
)

// Config parameterises Run. All fields are optional except KafkaConfig and Topic.
type Config struct {
	// KafkaConfig is passed directly to kafka.NewProducer (bootstrap.servers,
	// SASL credentials, etc. must already be populated).
	KafkaConfig kafka.ConfigMap
	// Topic is the destination topic for every produced message.
	Topic string
	// NumMessages controls how many sample messages to produce (default 10).
	NumMessages int
	// Users is the sample key pool (default: canonical 6-name list).
	Users []string
	// Items is the sample value pool (default: canonical 5-item list).
	Items []string
	// Out receives human-readable progress and error lines. Defaults to io.Discard.
	Out io.Writer
}

// Run creates a producer, emits NumMessages sample events to Topic, flushes,
// drains delivery reports, and closes the producer. It returns early if ctx
// is cancelled.
func Run(ctx context.Context, cfg Config) error {
	if cfg.Topic == "" {
		return errors.New("producer: Topic is required")
	}
	if cfg.NumMessages == 0 {
		cfg.NumMessages = 10
	}
	if len(cfg.Users) == 0 {
		cfg.Users = defaultUsers
	}
	if len(cfg.Items) == 0 {
		cfg.Items = defaultItems
	}
	out := cfg.Out
	if out == nil {
		out = io.Discard
	}

	p, err := kafka.NewProducer(&cfg.KafkaConfig)
	if err != nil {
		return fmt.Errorf("producer: create: %w", err)
	}

	// Drain delivery reports from p.Events() concurrently with Produce + Flush.
	// Without this, Flush blocks forever: librdkafka counts undrained delivery
	// reports as "outstanding events", so Flush always returns >0 even after
	// every message has been ACKed by the broker.
	drainDone := make(chan struct{})
	go func() {
		defer close(drainDone)
		for e := range p.Events() {
			handleEvent(out, e)
		}
	}()

	topic := cfg.Topic
	for n := 0; n < cfg.NumMessages; n++ {
		if err := ctx.Err(); err != nil {
			break
		}
		key := cfg.Users[rand.Intn(len(cfg.Users))]  // #nosec G404 -- sample data, not security-sensitive
		data := cfg.Items[rand.Intn(len(cfg.Items))] // #nosec G404 -- sample data, not security-sensitive
		if err := p.Produce(&kafka.Message{
			TopicPartition: kafka.TopicPartition{Topic: &topic, Partition: kafka.PartitionAny},
			Key:            []byte(key),
			Value:          []byte(data),
		}, nil); err != nil {
			var kErr kafka.Error
			if errors.As(err, &kErr) && kErr.Code() == kafka.ErrQueueFull {
				_, _ = fmt.Fprintln(out, "Producer queue full; flushing and retrying")
				p.Flush(1000)
				n--
				continue
			}
			_, _ = fmt.Fprintf(out, "Failed to produce message: %v\n", err)
		}
	}

	// Flush waits for all queued messages to be delivered AND for the drain
	// goroutine above to consume the resulting delivery reports.
	for p.Flush(1000) > 0 {
		_, _ = fmt.Fprintln(out, "Still waiting to flush outstanding messages")
		if err := ctx.Err(); err != nil {
			break
		}
	}
	// Closing the producer closes p.Events(), which unblocks the drain goroutine.
	p.Close()
	<-drainDone
	return nil
}

func handleEvent(out io.Writer, e kafka.Event) {
	switch ev := e.(type) {
	case *kafka.Message:
		if ev.TopicPartition.Error != nil {
			_, _ = fmt.Fprintf(out, "Failed to deliver message: %v\n", ev.TopicPartition)
		} else {
			_, _ = fmt.Fprintf(out, "Produced event to topic %s: key = %-10s value = %s\n",
				*ev.TopicPartition.Topic, string(ev.Key), string(ev.Value))
		}
	case kafka.Error:
		_, _ = fmt.Fprintf(out, "Error: %v\n", ev)
	default:
		_, _ = fmt.Fprintf(out, "Ignored event: %s\n", ev)
	}
}
