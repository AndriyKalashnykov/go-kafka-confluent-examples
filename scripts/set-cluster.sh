#!/bin/bash
# set -x

export CONFLUENT_ENV=
export CONFLUENT_CLUSTER=
export CONFLUENT_BOOTSTRAP_SERVER=

confluent environment use $CONFLUENT_ENV
confluent kafka cluster use $CONFLUENT_CLUSTER
confluent login --save
