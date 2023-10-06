#!/bin/bash
# set -x

export CONFLUENT_API_KEY=
export CONFLUENT_API_SECRET=

confluent api-key use $CONFLUENT_API_KEY --resource $CONFLUENT_CLUSTER
