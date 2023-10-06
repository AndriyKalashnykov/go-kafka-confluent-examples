package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/AndriyKalashnykov/go-kafka-confluent-examples/internal/util"
	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
)

func main() {

	configFile := util.ReadEnvVar(util.KafkaConfigFileEnv)
	conf := util.ReadConfig(configFile)

	conf.SetKey(util.SaslUserName, util.ReadEnvVar(util.SaslUserNameEnv))
	conf.SetKey(util.SaslPwd, util.ReadEnvVar(util.SaslPwdEnv))

	conf["group.id"] = "kafka-go-getting-started"
	conf["auto.offset.reset"] = "earliest"

	c, err := kafka.NewConsumer(&conf)

	if err != nil {
		fmt.Printf("Failed to create consumer: %s", err)
		os.Exit(1)
	}

	topic := util.ReadEnvVar(util.KafkaTopicEnv)
	fmt.Printf("Reading topic %v\n", topic)

	err = c.SubscribeTopics([]string{topic}, nil)
	if err != nil {
		fmt.Printf("Failed to subscrite to topic: %s", err)
		os.Exit(1)
	}

	// Set up a channel for handling Ctrl-C, etc
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)

	// Process messages
	run := true
	for run {
		select {
		case sig := <-sigchan:
			fmt.Printf("Caught signal %v: terminating\n", sig)
			run = false
		default:
			ev, err := c.ReadMessage(100 * time.Millisecond)
			if err != nil {
				// Errors are informational and automatically handled by the consumer
				continue
			}
			fmt.Printf("Consumed event from topic %s: key = %-10s value = %s\n",
				*ev.TopicPartition.Topic, string(ev.Key), string(ev.Value))
		}
	}

	c.Close()

}
