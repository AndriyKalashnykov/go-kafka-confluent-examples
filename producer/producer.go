package main

import (
	"fmt"
	"math/rand"
	"os"
	"time"

	"github.com/AndriyKalashnykov/go-kafka-confluent-examples/internal/util"
	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
)

func main() {

	configFile := util.ReadEnvVar(util.KafkaConfigFileEnv)
	conf := util.ReadConfig(configFile)

	conf.SetKey(util.SaslUserName, util.ReadEnvVar(util.SaslUserNameEnv))
	conf.SetKey(util.SaslPwd, util.ReadEnvVar(util.SaslPwdEnv))

	topic := util.ReadEnvVar(util.KafkaTopicEnv)
	p, err := kafka.NewProducer(&conf)

	if err != nil {
		fmt.Printf("Failed to create producer: %s", err)
		os.Exit(1)
	}

	// Go-routine to handle message delivery reports and
	// possibly other event types (errors, stats, etc)
	go func() {
		for e := range p.Events() {
			switch ev := e.(type) {
			case *kafka.Message:
				if ev.TopicPartition.Error != nil {
					fmt.Printf("Failed to deliver message: %v\n", ev.TopicPartition)
				} else {
					fmt.Printf("Produced event to topic %s: key = %-10s value = %s\n",
						*ev.TopicPartition.Topic, string(ev.Key), string(ev.Value))
				}
			case kafka.Error:
				// Generic client instance-level errors, such as
				// broker connection failures, authentication issues, etc.
				//
				// These errors should generally be considered informational
				// as the underlying client will automatically try to
				// recover from any errors encountered, the application
				// does not need to take action on them.
				fmt.Printf("Error: %v\n", ev)
			default:
				fmt.Printf("Ignored event: %s\n", ev)
			}
		}
	}()

	users := [...]string{"eabara", "jsmith", "sgarcia", "jbernard", "htanaka", "awalther"}
	items := [...]string{"book", "alarm clock", "t-shirts", "gift card", "batteries"}

	for n := 0; n < 10; n++ {
		key := users[rand.Intn(len(users))]
		data := items[rand.Intn(len(items))]
		p.Produce(&kafka.Message{
			TopicPartition: kafka.TopicPartition{Topic: &topic, Partition: kafka.PartitionAny},
			Key:            []byte(key),
			Value:          []byte(data),
		}, nil)

		if err != nil {
			if err.(kafka.Error).Code() == kafka.ErrQueueFull {
				// Producer queue is full, wait 1s for messages
				// to be delivered then try again.
				time.Sleep(time.Second)
				continue
			}
			fmt.Printf("Failed to produce message: %v\n", err)
		}
	}

	// Flush and close the producer and the events channel
	for p.Flush(10000) > 0 {
		fmt.Print("Still waiting to flush outstanding messages\n")
	}
	p.Close()
}
