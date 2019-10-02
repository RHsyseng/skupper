#!/bin/bash

    skupper -n skuppman-db -c west2 init --id west2 
    skupper -n skuppman-db -c west2 connection-token tok-east1-west2.yaml
    skupper -n skuppman-db -c west2 connection-token tok-east2-west2.yaml


    skupper -n skuppman-db -c east2 init --id east2
    skupper -n skuppman-db -c east2 connection-token tok-east1-east2.yaml

    skupper -n skuppman-db -c east2 connect tok-east2-west2.yaml

    # make east1 the private (pretend) cluster
    skupper -n skuppman-db -c east1 init --id east1 --edge
    skupper -n skuppman-db -c east1 connect tok-east1-east2.yaml
    skupper -n skuppman-db -c east1 connect tok-east1-west2.yaml

