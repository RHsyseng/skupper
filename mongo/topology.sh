#!/bin/bash
# From https://github.com/skupperproject/skupper-example-mongodb-replica-set#step-2-define-cluster-topology-values
# Define environmental variables for SKUPPER

export SKUPPER_PUBLIC_CLUSTER_COUNT=3
export SKUPPER_PRIVATE_CLUSTER_COUNT=0
export SKUPPER_NAMESPACE="sku-mongo"
export SKUPPER_PUBLIC_CLUSTER_SUFFIX_1="east-1.sysdeseng.com"
export SKUPPER_PUBLIC_CLUSTER_SUFFIX_2="east-2.sysdeseng.com"
export SKUPPER_PUBLIC_CLUSTER_SUFFIX_3="west-2.sysdeseng.com"
export SKUPPER_PUBLIC_CLUSTER_NAME_1="east-1"
export SKUPPER_PUBLIC_CLUSTER_NAME_2="east-2"
export SKUPPER_PUBLIC_CLUSTER_NAME_3="west-2"

export SKUPPER_PRIVATE_CLUSTER_NAME_1="east-1"
export SKUPPER_PRIVATE_CLUSTER_SUFFIX_1="east-1.sysdeseng.com"
export SKUPPER_PRIVATE_CLUSTER_LOCAL_IP_1="apps"
