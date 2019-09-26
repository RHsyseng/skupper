# Combining Skupper and GitOps using PacMan

[Skupper MongoDB Multi-Cluster RS](https://github.com/skupperproject/skupper-example-mongodb-replica-set)

[ArgoCD GitOps](https://argoproj.github.io/argo-cd)

and 

[Pacman](https://github.com/font/k8s-example-apps/blob/master/pacman-nodejs-app)

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

- Generate a network.conf file defining routers and connections
- Pass this network.conf through a python3 script running in a container to get a tar file
- Unpack the tar file to find a yaml file for each cluster

The `network.conf` looks like a simplified version of the Apache Qpid dispatch router [qdrouter.conf](http://qpid.apache.org/releases/qpid-dispatch-1.9.0/man/qdrouterd.conf.html). Directives in the file include:

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

Following [the Skoot repository README](https://github.com/skupperproject/skoot/blob/master/README.md), pipe the above 
`network.conf` file through the skoot container hosted on [Quay.io](https://quay.io/skupper/skoot/) which emits a tar
file on standard out:

    cat network.conf | docker run -i quay.io/skupper/skoot | tar --extract

The above command will create a directory `yaml` with files corresponding to resources to be created on each cluster
for the routers. Each file contains several (five in our example) resources. You can see what kind of files exist in 
each cluster's config with grep:

    grep ^kind yaml/east-1.yaml 
    
    kind: Secret
    kind: ConfigMap
    kind: Service
    kind: Deployment
    kind: Route

Before proceeding with adding these resources to the clusters or to Argo CD, start by creating the repository they will
be maintained in.

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

Using Kustomize and ArgoCD together allows for the reuse of similar bits of code.
Now is a good time to break up the previously created skoot yaml files into
individual files for adding to ArgoCD.

For this example, create applications `mongo` and `pacman`. The skupper router
and content will go in the mongo application.

    mkdir -p pacman/base mongo/{base,overlays/{east-1,east-2,west-2}}

To divide the clusters' yaml files by the --- separator, use the 
Gnu csplit utility:

    for cluster in east-1 east-2 west-2
    do
        csplit --prefix "mongo/overlays/${cluster}/" --suffix "%02d.yaml" \
          yaml/${cluster}.yaml '/^---$/' '{*}'
    done

This creates a set of numbered yaml files in each overlay directory as so:

    grep -r ^kind mongo/overlays/
    
    mongo/overlays/east-1/02.yaml:kind: Service
    mongo/overlays/east-1/03.yaml:kind: Deployment
    mongo/overlays/east-1/01.yaml:kind: ConfigMap
    mongo/overlays/east-1/00.yaml:kind: Secret
    mongo/overlays/east-1/04.yaml:kind: Route
    mongo/overlays/east-2/02.yaml:kind: Service
    mongo/overlays/east-2/03.yaml:kind: Deployment
    mongo/overlays/east-2/01.yaml:kind: ConfigMap
    mongo/overlays/east-2/00.yaml:kind: Secret
    mongo/overlays/east-2/04.yaml:kind: Route
    mongo/overlays/west-2/02.yaml:kind: Service
    mongo/overlays/west-2/03.yaml:kind: Deployment
    mongo/overlays/west-2/01.yaml:kind: ConfigMap
    mongo/overlays/west-2/00.yaml:kind: Secret
    mongo/overlays/west-2/04.yaml:kind: Route

### Find Duplicated Configurations for Base

The next task is to figure out which of these files differ from cluster to
cluster, and which do not. The `md5sum` utility comes in handy here:

    md5sum mongo/overlays/*/*.yaml | sort
    1812bdf28176a3a1a8da866cb26f7008  mongo/overlays/east-1/02.yaml
    1812bdf28176a3a1a8da866cb26f7008  mongo/overlays/east-2/02.yaml
    1812bdf28176a3a1a8da866cb26f7008  mongo/overlays/west-2/02.yaml
    341ef8c0a6478d240fce855cad62e429  mongo/overlays/east-1/00.yaml
    4a66c6dc175949fb97098d5b5fa539f0  mongo/overlays/west-2/04.yaml
    6105347ebb9825ac754615ca55ff3b0c  mongo/overlays/east-1/05.yaml
    6105347ebb9825ac754615ca55ff3b0c  mongo/overlays/east-2/05.yaml
    6105347ebb9825ac754615ca55ff3b0c  mongo/overlays/west-2/05.yaml
    7af94f0753aa5e0c65c51a5e6641761d  mongo/overlays/east-1/04.yaml
    7dffde783e42f18985c6f954405d82a6  mongo/overlays/east-1/01.yaml
    83e8ad3eb1ed107d615169481a6f8c32  mongo/overlays/east-1/03.yaml
    83e8ad3eb1ed107d615169481a6f8c32  mongo/overlays/east-2/03.yaml
    83e8ad3eb1ed107d615169481a6f8c32  mongo/overlays/west-2/03.yaml
    afb947c44d02a107406ad304e4a3acfa  mongo/overlays/east-2/04.yaml
    bedc1fb0cde60c3a2252fed90f7ae546  mongo/overlays/west-2/00.yaml
    d08d3a7056a019e08c5fdf38973e0fb2  mongo/overlays/west-2/01.yaml
    f096e63d540955607213d71eb7801ebd  mongo/overlays/east-2/01.yaml
    f9025d7ccde06fd08ef2a5f10b61f365  mongo/overlays/east-2/00.yaml

Note that in this sorted list, all the `02.yaml`, `05.yaml`, and `03.yaml` are alike. The `05.yaml` is actually just a fragment created with only "---" and should be discarded.

    rm mongo/overlays/*/05.yaml

From above, `02.yaml` contains a Service while `03.yaml` contains a Deployment so they may be moved to base thus:

    mv mongo/overlays/west-2/02.yaml mongo/base/service.yaml
    mv mongo/overlays/west-2/03.yaml mongo/base/deployment.yaml

Removing the duplicates in the `east-*` clusters:

    rm mongo/overlays/east-?/0{2,3}.yaml





### Create ArgoCD Application


### Find Unique Configurations for Overrides
