#!/bin/bash
# set -x

sed -e "s%BTSTRP%$CONFLUENT_BOOTSTRAP_SERVER%g" ./tmpl/kafka.properties.tmpl > ./kafka.properties

sed -e "s%BTSTRP%$CONFLUENT_BOOTSTRAP_SERVER%g" -e "s%APIKEY%$CONFLUENT_API_KEY%g" -e "s%APISECRET%$CONFLUENT_API_SECRET%g" ./tmpl/.env.tmpl > ./.env

kubectl create configmap kafka-config --from-file kafka.properties -o yaml --dry-run=client >./k8s/cm.yaml
sed -e"s%USR%`echo -n $CONFLUENT_API_KEY|base64 -w0`%g" -e "s%PWD%`echo -n $CONFLUENT_API_SECRET|base64 -w0`%g" ./tmpl/sc.yaml.tmpl > ./k8s/sc.yaml
