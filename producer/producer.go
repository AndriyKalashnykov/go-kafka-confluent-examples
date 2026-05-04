// Producer entrypoint. The thin shell here delegates env-var translation
// to internal/util.BuildKafkaConfigMap (testable, returns errors instead
// of os.Exit) and the produce loop to internal/producer.Run (testable,
// driven by ctx + Config).
package main

import (
	"context"
	"fmt"
	"os"
	"strconv"

	"github.com/AndriyKalashnykov/go-kafka-confluent-examples/internal/producer"
	"github.com/AndriyKalashnykov/go-kafka-confluent-examples/internal/util"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	conf, topic, err := util.BuildKafkaConfigMap(os.Getenv)
	if err != nil {
		return fmt.Errorf("producer: build config: %w", err)
	}
	cfg := producer.Config{
		KafkaConfig: conf,
		Topic:       topic,
		Out:         os.Stdout,
	}
	if v := os.Getenv(util.NumMessagesEnv); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			return fmt.Errorf("producer: invalid %s=%q: %w", util.NumMessagesEnv, v, err)
		}
		cfg.NumMessages = n
	}
	return producer.Run(context.Background(), cfg)
}
