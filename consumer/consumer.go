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
	configFile := util.ReadEnvVar(util.KafkaConfigFileEnv)
	conf := util.ReadConfig(configFile)

	if err := conf.SetKey(util.SaslUserName, util.ReadEnvVar(util.SaslUserNameEnv)); err != nil {
		fmt.Printf("Failed to set %s: %s\n", util.SaslUserName, err)
		os.Exit(1)
	}
	if err := conf.SetKey(util.SaslPwd, util.ReadEnvVar(util.SaslPwdEnv)); err != nil {
		fmt.Printf("Failed to set %s: %s\n", util.SaslPwd, err)
		os.Exit(1)
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

	topic := util.ReadEnvVar(util.KafkaTopicEnv)
	if err := consumer.Run(ctx, consumer.Config{
		KafkaConfig: conf,
		Topic:       topic,
		Out:         os.Stdout,
	}); err != nil {
		fmt.Printf("Consumer failed: %s\n", err)
		os.Exit(1)
	}
}
