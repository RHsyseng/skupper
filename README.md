# Combining Skupper and GitOps using

[Skupper MongoDB Multi-Cluster RS](https://github.com/skupperproject/skupper-example-mongodb-replica-set)

and

[ArgoCD GitOps](https://argoproj.github.io/argo-cd)

Private repo because we will keep SSL keys here.

## Generating Skupper Configs

The Skupper MongoDB example above has recently been changed over from the
[Skoot configuration generator](https://github.com/skupperproject/skoot) to use
the [Skupper Commandline
Utility](https://github.com/skupperproject/skupper-cli). We must change back to
using skoot for our GitOps workflow because it deals in yaml files, whereas
skupper-cli expects to interact directly with the target clusters.

### Gather Information

The process for using skoot goes like this:

- Generate a router.conf file defining routers and connections
- Pass this network.conf through a python3 script running in a container to get a tar file
- Unpack the tar file to find a yaml file for each cluster

The `router.conf` looks like a simplified version of the Apache Qpid dispatch router [qdrouter.conf](http://qpid.apache.org/releases/qpid-dispatch-1.9.0/man/qdrouterd.conf.html). Directives in the file include:

(Router|EdgeRouter) <cluster> <hostname>

Connect <cluster1> <cluster2>

Console <cluster> <hostname>

For example, to connect three public clusters, east-1, east-2, and west-2:

```
Router east-1 inter-router.<namespace>.apps.east-1.example.com
Router east-2 inter-router.<namespace>.apps.east-2.example.com
Router west-2 inter-router.<namespace>.apps.west-2.example.com
Connect east-1 east-2
Connect east-1 west-2
Connect east-2 west-2
Console east-1 console.<namespace>.apps.east-1.example.com

```

### Create Kustomize Directory Structure
Create a Git repository (preferably private) with the following directory layout:

    .
    ├── application1            # Group applications separately, e.g. database, front end
    │   ├── base                # Files common to deployment in all clusters
    │   └── overlays
    │       ├── cluster1        # Customizations for cluster1
    │       ├── cluster2        # Customizations for cluster2
    │       └── clusterN        # Customizations for clusterN
    └── application2            # Documentation files (alternatively `doc`)
        ├── base                # Files common to deployment in all clusters
        └── overlays
            ├── cluster1        # Customizations for cluster1
            ├── cluster2        # Customizations for cluster2
            └── clusterN        # Customizations for clusterN

Using Kustomize and ArgoCD together 

### Create ArgoCD Application

### Find Duplicated Configurations for Base

### Find Unique Configurations for Overrides
