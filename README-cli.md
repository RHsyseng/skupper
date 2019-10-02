# Skupper CLI with pacman (and argo cd)

Step 1 follow along with [The Skupper project mongo replica set
demo](https://github.com/skupperproject/skupper-example-mongodb-replica-set)
to download the skupper command line tool and clone the example code repository.

Set up your kubeconfig with a context per cluster, we will use east1, east2,
and west2 for our example.

# Argo CD setup

Create apps skuppman-db-<clustername> for each cluster pointing at the git repo
structured with overlays for each cluster

    argocd app create --project default \
    --name skuppman-db-east1 \
    --repo https://github.com/RHsyseng/skuppman \
    --dest-namespace skuppman-db \
    --revision master \
    --sync-policy none \
    --path skuppman-db/overlays/east1 \
    --dest-server https://kubernetes.default.svc

    argocd app create --project default \
    --name skuppman-db-east2 \
    --repo https://github.com/RHsyseng/skuppman \
    --dest-namespace skuppman-db \
    --revision master \
    --sync-policy none \
    --path skuppman-db/overlays/east2 \
    --dest-server https://api.east-2.example.com:6443

    argocd app create --project default \
    --name skuppman-db-west2 \
    --repo https://github.com/RHsyseng/skuppman \
    --dest-namespace skuppman-db \
    --revision master \
    --sync-policy none \
    --path skuppman-db/overlays/west2 \
    --dest-server https://api.west-2.example.com:6443


For the skupper inits use `-c` to select contexts and `-n` to select the skuppman-db namespace.

    skupper -n skuppman-db -c east1 init --id east1

Each connection needs to be established in a single direction between two clusters to interconnect
We are using all publicly available clusters, but may pretend that west2 is on premise, not directly
accessible from the outside.

In that case, tokens need to be created on east1 for the connection from east2 and west2, as well as
on east2 for the connection from west2.

    skupper -n skuppman-db -c east1 connection-token tok-east2-east1.yaml
    skupper -n skuppman-db -c east1 connection-token tok-west2-east1.yaml

The following operations use the east2 context:

    skupper -n skuppman-db -c east2 init --id east2
    skupper -n skuppman-db -c east2 init connection-token tok-west2-east2.yaml

Establish a connection between east1 and east2

    skupper -n skuppman-db -c east2 connect tok-east2-east1.yaml

To establish west2 as a private cluster, use the `--edge` modifier.

    skupper -n skuppman-db -c west2 init --id west2 --edge
    skupper -n skuppman-db -c west2 connect tok-west2-east1.yaml
    skupper -n skuppman-db -c west2 connect tok-west2-east2.yaml

To export the whole lot to yaml files, loop around the clusters, then around
the objects:

    for c in east1 east2 west2
    do
        for res in $(oc --context $c -n skuppman-db \
            get deployments,sa,secret -o name \
            | grep -v -E '(builder|default|deployer|dockercfg)'
            )
        do
            file="${c}/$(dirname $res)-$(basename $res)"
            oc --context $c -n skuppman-db \
                get $res -o yaml --export > $file
        done
    done
