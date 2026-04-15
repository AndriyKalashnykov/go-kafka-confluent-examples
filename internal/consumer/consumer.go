// Package consumer drives a Confluent Kafka consumer from a supplied config.
//
// The core loop is exposed as Run(ctx, cfg) so it can be exercised against a
// real broker in integration tests without pulling in os.Exit, signal handling,
// or env-var plumbing. Run returns cleanly when ctx is cancelled OR when
// MaxMessages is reached (zero means unlimited).
package consumer

import (
	"context"
	"errors"
	"fmt"
	"io"
	"time"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
)

// Config parameterises Run. KafkaConfig and Topic are required.
type Config struct {
	// KafkaConfig is passed directly to kafka.NewConsumer. If group.id /
	// auto.offset.reset are absent, Run fills in safe defaults.
	KafkaConfig kafka.ConfigMap
	// Topic is the topic to subscribe to.
	Topic string
	// GroupID overrides KafkaConfig["group.id"]. Default: "kafka-go-getting-started".
	GroupID string
	// AutoOffsetReset overrides KafkaConfig["auto.offset.reset"]. Default: "earliest".
	AutoOffsetReset string
	// MaxMessages bounds how many messages to consume before returning nil.
	// Zero means unlimited (drive termination via ctx cancel).
	MaxMessages int
	// PollTimeout is the per-ReadMessage deadline. Default: 100ms.
	PollTimeout time.Duration
	// Out receives human-readable progress lines. Defaults to io.Discard.
	Out io.Writer
}

// Run creates a consumer, subscribes to Topic, and reads messages until ctx is
// cancelled or MaxMessages is reached. It always closes the consumer cleanly.
func Run(ctx context.Context, cfg Config) error {
	if cfg.Topic == "" {
		return errors.New("consumer: Topic is required")
	}
	if cfg.GroupID == "" {
		if _, ok := cfg.KafkaConfig["group.id"]; !ok {
			cfg.GroupID = "kafka-go-getting-started"
		}
	}
	if cfg.GroupID != "" {
		if err := cfg.KafkaConfig.SetKey("group.id", cfg.GroupID); err != nil {
			return fmt.Errorf("consumer: set group.id: %w", err)
		}
	}
	if cfg.AutoOffsetReset == "" {
		if _, ok := cfg.KafkaConfig["auto.offset.reset"]; !ok {
			cfg.AutoOffsetReset = "earliest"
		}
	}
	if cfg.AutoOffsetReset != "" {
		if err := cfg.KafkaConfig.SetKey("auto.offset.reset", cfg.AutoOffsetReset); err != nil {
			return fmt.Errorf("consumer: set auto.offset.reset: %w", err)
		}
	}
	poll := cfg.PollTimeout
	if poll == 0 {
		poll = 100 * time.Millisecond
	}
	out := cfg.Out
	if out == nil {
		out = io.Discard
	}

	c, err := kafka.NewConsumer(&cfg.KafkaConfig)
	if err != nil {
		return fmt.Errorf("consumer: create: %w", err)
	}
	defer func() {
		if err := c.Close(); err != nil {
			_, _ = fmt.Fprintf(out, "Failed to close consumer: %v\n", err)
		}
	}()

	if err := c.SubscribeTopics([]string{cfg.Topic}, nil); err != nil {
		return fmt.Errorf("consumer: subscribe: %w", err)
	}
	_, _ = fmt.Fprintf(out, "Reading topic %v\n", cfg.Topic)

	count := 0
	for {
		if err := ctx.Err(); err != nil {
			return nil
		}
		ev, err := c.ReadMessage(poll)
		if err != nil {
			// Timeout/transient errors — the underlying client retries.
			continue
		}
		_, _ = fmt.Fprintf(out, "Consumed event from topic %s: key = %-10s value = %s\n",
			*ev.TopicPartition.Topic, string(ev.Key), string(ev.Value))
		count++
		if cfg.MaxMessages > 0 && count >= cfg.MaxMessages {
			return nil
		}
	}
}
