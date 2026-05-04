// Consumer entrypoint. The thin shell here delegates env-var translation
// to internal/util.BuildKafkaConfigMap (testable, returns errors instead
// of os.Exit), wires SIGINT/SIGTERM to ctx-cancel, and hands off to
// internal/consumer.Run (testable, driven by ctx + Config).
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/AndriyKalashnykov/go-kafka-confluent-examples/internal/consumer"
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
		return fmt.Errorf("consumer: build config: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		sig := <-sigchan
		fmt.Printf("Caught signal %v: terminating\n", sig)
		cancel()
	}()

	return consumer.Run(ctx, consumer.Config{
		KafkaConfig: conf,
		Topic:       topic,
		Out:         os.Stdout,
	})
}
