package util

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadEnvVar(t *testing.T) {
	tests := []struct {
		name    string
		key     string
		envVal  string
		setEnv  bool
		wantVal string
	}{
		{name: "set value", key: "TEST_SET", envVal: "hello", setEnv: true, wantVal: "hello"},
		{name: "unset returns empty", key: "TEST_UNSET", setEnv: false, wantVal: ""},
		{name: "empty string set", key: "TEST_EMPTY", envVal: "", setEnv: true, wantVal: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.setEnv {
				t.Setenv(tt.key, tt.envVal)
			} else {
				if err := os.Unsetenv(tt.key); err != nil {
					t.Fatalf("Unsetenv(%q): %v", tt.key, err)
				}
			}
			if got := ReadEnvVar(tt.key); got != tt.wantVal {
				t.Errorf("ReadEnvVar(%q) = %q, want %q", tt.key, got, tt.wantVal)
			}
		})
	}
}

func TestReadConfig(t *testing.T) {
	dir := t.TempDir()

	tests := []struct {
		name     string
		contents string
		want     map[string]string
	}{
		{
			name:     "basic key=value",
			contents: "bootstrap.servers=broker:9092\nsecurity.protocol=SASL_SSL\n",
			want:     map[string]string{"bootstrap.servers": "broker:9092", "security.protocol": "SASL_SSL"},
		},
		{
			name:     "ignores comments and blank lines",
			contents: "# header\n\nkey=value\n  # indented comment, not stripped\n",
			want:     map[string]string{"key": "value"},
		},
		{
			name:     "trims whitespace around key and value",
			contents: "  key1  =  value1  \nkey2=value2\n",
			want:     map[string]string{"key1": "value1", "key2": "value2"},
		},
		{
			name:     "preserves '=' in value",
			contents: "sasl.jaas.config=org.apache.kafka=foo\n",
			want:     map[string]string{"sasl.jaas.config": "org.apache.kafka=foo"},
		},
		{
			name:     "skips lines without '='",
			contents: "this has no equals\nkey=value\n",
			want:     map[string]string{"key": "value"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(dir, tt.name+".properties")
			if err := os.WriteFile(path, []byte(tt.contents), 0o600); err != nil {
				t.Fatal(err)
			}

			got := ReadConfig(path)
			if len(got) != len(tt.want) {
				t.Fatalf("len(ReadConfig) = %d, want %d — got: %v", len(got), len(tt.want), got)
			}
			for k, wantV := range tt.want {
				gotV, ok := got[k]
				if !ok {
					t.Errorf("missing key %q", k)
					continue
				}
				if gotV != wantV {
					t.Errorf("key %q: got %q, want %q", k, gotV, wantV)
				}
			}
		})
	}
}

func TestReadConfig_EmptyFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "empty.properties")
	if err := os.WriteFile(path, []byte(""), 0o600); err != nil {
		t.Fatal(err)
	}
	got := ReadConfig(path)
	if len(got) != 0 {
		t.Errorf("empty file: got %v, want empty map", got)
	}
}

func TestConstants(t *testing.T) {
	// Sanity check constants haven't silently drifted — these strings land in
	// Kafka config keys and environment variable names used by Confluent Cloud.
	cases := map[string]string{
		SaslUserNameEnv:    "SASL_USERNAME",
		SaslUserName:       "sasl.username",
		SaslPwdEnv:         "SASL_PASSWORD",
		SaslPwd:            "sasl.password",
		KafkaConfigFileEnv: "KAFKA_CONFIG_FILE",
		KafkaTopicEnv:      "KAFKA_TOPIC",
	}
	for got, want := range cases {
		if got != want {
			t.Errorf("constant drift: %q, want %q", got, want)
		}
	}
}
