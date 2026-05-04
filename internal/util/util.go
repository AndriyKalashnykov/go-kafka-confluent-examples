// Package util holds the env-var → kafka.ConfigMap plumbing shared between
// the producer and consumer entrypoints. Splitting it out here makes the
// main() functions a thin shell and lets the env-handling logic be unit
// tested without spawning subprocesses.
package util

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
)

const (
	SaslUserNameEnv    = "SASL_USERNAME"
	SaslUserName       = "sasl.username"
	SaslPwdEnv         = "SASL_PASSWORD"
	SaslPwd            = "sasl.password"
	KafkaConfigFileEnv = "KAFKA_CONFIG_FILE"
	KafkaTopicEnv      = "KAFKA_TOPIC"
	// NumMessagesEnv is read by the producer entrypoint to override the
	// default Config.NumMessages (10). E2E harnesses set this to fix the
	// publish count for assertion-counting purposes.
	NumMessagesEnv = "NUM_MESSAGES"
)

// EnvLookup is the minimal env-reader contract — `os.Getenv` satisfies it
// directly, and tests pass a map-backed implementation.
type EnvLookup func(string) string

// ReadEnvVar returns the value of key. Empty string when unset; logs a
// notice to stdout in that case to surface unset-required-vars at boot.
func ReadEnvVar(key string) string {
	val, ok := os.LookupEnv(key)
	if !ok {
		fmt.Printf("%s not set\n", key)
		return ""
	}
	return val
}

// ReadConfig parses a Java-style .properties file into a kafka.ConfigMap.
// Returns an error on missing file, scanner failure, or any other read
// problem so callers can decide how to surface the error (vs. the legacy
// os.Exit-on-error which made the function untestable).
func ReadConfig(configFile string) (kafka.ConfigMap, error) {
	file, err := os.Open(configFile) // #nosec G304 -- configFile sourced from trusted KAFKA_CONFIG_FILE env var
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", configFile, err)
	}
	defer func() { _ = file.Close() }()

	m := make(kafka.ConfigMap)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "#") || line == "" {
			continue
		}
		before, after, found := strings.Cut(line, "=")
		if !found {
			continue
		}
		m[strings.TrimSpace(before)] = strings.TrimSpace(after)
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("read %s: %w", configFile, err)
	}
	return m, nil
}

// BuildKafkaConfigMap is the canonical env-var-to-ConfigMap translation
// used by both producer and consumer entrypoints: read the .properties
// file path from KAFKA_CONFIG_FILE, parse it, then layer in SASL
// credentials from SASL_USERNAME / SASL_PASSWORD env vars. Returns the
// merged ConfigMap and the topic from KAFKA_TOPIC.
//
// Pass `os.Getenv` for production; tests pass a map-backed fake.
func BuildKafkaConfigMap(lookup EnvLookup) (kafka.ConfigMap, string, error) {
	configFile := lookup(KafkaConfigFileEnv)
	if configFile == "" {
		return nil, "", fmt.Errorf("%s is required", KafkaConfigFileEnv)
	}
	conf, err := ReadConfig(configFile)
	if err != nil {
		return nil, "", err
	}
	if err := conf.SetKey(SaslUserName, lookup(SaslUserNameEnv)); err != nil {
		return nil, "", fmt.Errorf("set %s: %w", SaslUserName, err)
	}
	if err := conf.SetKey(SaslPwd, lookup(SaslPwdEnv)); err != nil {
		return nil, "", fmt.Errorf("set %s: %w", SaslPwd, err)
	}
	return conf, lookup(KafkaTopicEnv), nil
}
