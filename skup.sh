#!/bin/bash
set -x

oc create ns skuppman-db --context east1
oc create ns skuppman-db --context east2
oc create ns skuppman-db --context west2

skupper -n skuppman-db -c west2 init --id west2 
skupper -n skuppman-db -c west2 connection-token tok-east1-west2.yaml
skupper -n skuppman-db -c west2 connection-token tok-east2-west2.yaml


skupper -n skuppman-db -c east2 init --id east2
skupper -n skuppman-db -c east2 connection-token tok-east1-east2.yaml

skupper -n skuppman-db -c east2 connect tok-east2-west2.yaml

# make east1 the private (pretend) cluster
skupper -n skuppman-db -c east1 init --id east1 --edge

sleep 5

skupper -n skuppman-db -c east1 connect tok-east1-east2.yaml
skupper -n skuppman-db -c east1 connect tok-east1-west2.yaml

oc --context east1 -n skuppman-db apply -f ~/git/skupper-example-mongodb-replica-set/deployment-mongo-svc-a.yaml
oc --context east2 -n skuppman-db apply -f ~/git/skupper-example-mongodb-replica-set/deployment-mongo-svc-b.yaml
oc --context west2 -n skuppman-db apply -f ~/git/skupper-example-mongodb-replica-set/deployment-mongo-svc-c.yaml

# Annotate mongo pods
oc --context east1 -n skuppman-db annotate service mongo-svc-a skupper.io/proxy=tcp
oc --context east2 -n skuppman-db annotate service mongo-svc-b skupper.io/proxy=tcp
oc --context west2 -n skuppman-db annotate service mongo-svc-c skupper.io/proxy=tcp
