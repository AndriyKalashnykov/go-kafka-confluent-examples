package main

import (
	"context"
	"fmt"
	"os"

	"github.com/AndriyKalashnykov/go-kafka-confluent-examples/internal/producer"
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

	topic := util.ReadEnvVar(util.KafkaTopicEnv)
	if err := producer.Run(context.Background(), producer.Config{
		KafkaConfig: conf,
		Topic:       topic,
		Out:         os.Stdout,
	}); err != nil {
		fmt.Printf("Producer failed: %s\n", err)
		os.Exit(1)
	}
}
