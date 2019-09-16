## Testing Skupper plus GitOps using

[Skupper MongoDB Multi-Cluster RS](https://github.com/skupperproject/skupper-example-mongodb-replica-set)

and

[ArgoCD GitOps](https://argoproj.github.io/argo-cd)

Private repo because we will keep SSL keys here.

## Generating Configs

The Skupper MongoDB example above has recently been changed over from the [Skoot configuration generator](https://github.com/skupperproject/skoot) to use the [Skupper Commandline Utility](https://github.com/skupperproject/skupper-cli). We must change back to using skoot for our GitOps workflow because it deals in yaml files, whereas skupper-cli expects to interact directly with the target clusters.

### Gather Information

The process for using skoot goes like this:

- Generate a network.conf file defining routers and connections
- Pass this network.conf through a python3 script running in a container to get a tar file
- Unpack the tar file to find a yaml file for each cluster

### Create Kustomize Directory Structure

### Create ArgoCD Application

### Find Duplicated Configurations for Base

### Find Unique Configurations for Overrides
