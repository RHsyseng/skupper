# Combining Skupper and GitOps using PacMan

## What is Skupper

The Skupper project consists of a set of tooling to employ AMQP to enable multi-cluster networking between services in different clusters.

## Key Concepts

### Routers

Skupper operates by creating a router within a designated namespace for each cluster.
These routers may be normal routers (capable of establishing and recieving connections) or **edge** routers,
which may only establish connections to other routers, but not listen for connections themselves.
The case for using an edge router would be an on-premise cluster behind a prohibitive firewall.

### Connections

A connection describes a graph's edge between two routers.
Traffic may flow in either direction once established, but to establish the initial connection, direction is important.

### Tokens

Tokens are created in order to establish connections.
Tokens take the form of self-signed SSL certificates kept in Secrets and shared between two clusters requiring a connection.

### Proxies

Proxies are Pods running in one cluster which use the AMQP network to provide access to Services in another cluster.
In the Pacman example shown here, we create MongoDB pods in each of three clusters,
then use Skupper to create proxies of the MongoDB Services from each remote cluster in the appropriate namespace on each local cluster.
Accessing the MongoDB instance from a remote cluster is as simple as accessing the local instance.

## Resources

[Skupper Home Page](https://skupper.io/)

[Skupper MongoDB Multi-Cluster RS](https://github.com/skupperproject/skupper-example-mongodb-replica-set)

[Argo CD GitOps](https://argoproj.github.io/argo-cd)

and

[Pacman](https://github.com/font/k8s-example-apps/blob/master/pacman-nodejs-app)

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

```text
    (Router|EdgeRouter) <cluster> <hostname>

    Connect <cluster1> <cluster2>

    Console <cluster> <hostname>
```

For example, to connect three public clusters, east-1, east-2, and west-2:

```text
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

```bash
cat network.conf | docker run -i quay.io/skupper/skoot | tar --extract
```

The above command will create a directory `yaml` with files corresponding to resources to be created on each cluster
for the routers. Each file contains several (five in our example) resources. You can see what kind of resources exist in
each cluster's yaml with grep:

```bash
grep ^kind yaml/east-1.yaml

kind: Secret
kind: ConfigMap
kind: Service
kind: Deployment
kind: Route
```

Before proceeding with adding these resources to the clusters or to Argo CD, start by creating the repository they will
be maintained in.

### Create Kustomize Directory Structure

Next we will create a Git repository (preferably private) following the following directory layout:

```bash
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
```

Using Kustomize and Argo CD together allows for the reuse of similar bits of code.
Now is a good time to break up the previously created skoot yaml files into
individual files for adding to Argo CD.

For this example, create applications `mongo` and `pacman`. The skupper router
and content will go in the mongo application.

```bash
mkdir -p pacman/base mongo/{base,overlays/{east-1,east-2,west-2}}
```

To divide the clusters' yaml files by the --- separator, use the
Gnu csplit utility:

```bash
for cluster in east-1 east-2 west-2
do
    csplit --prefix "mongo/overlays/${cluster}/" --suffix "%02d.yaml" \
         yaml/${cluster}.yaml '/^---$/' '{*}'
done
```

This creates a set of numbered yaml files in each overlay directory as so:

```text
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
```

### Find Duplicated Configurations for Base

The next task is to figure out which of these files differ from cluster to
cluster, and which do not. The `md5sum` utility comes in handy here:

```bash
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
```

Note that in this sorted list, all the `02.yaml`, `05.yaml`, and `03.yaml` are alike. The `05.yaml` is actually just a fragment created with only "---" and should be discarded.

```bash
rm mongo/overlays/*/05.yaml
```

From above, `02.yaml` contains a Service while `03.yaml` contains a Deployment so they may be moved to base thus:

```bash
mv mongo/overlays/west-2/02.yaml mongo/base/service.yaml
mv mongo/overlays/west-2/03.yaml mongo/base/deployment.yaml
```

Removing the duplicates in the `east-*` clusters:

```bash
rm mongo/overlays/east-?/0{2,3}.yaml
```

### Find Unique Configurations for Overrides

We are left with Secrets in `00.yaml`, ConfigMaps in `01.yaml`, and Routes in `04.yaml` so we can clean up the file
names with a quick for loop:

```bash
for cluster in east-1 east-2 west-2
do
    d=mongo/overlays/${cluster}
    mv $d/00.yaml $d/secret.yaml
    mv $d/01.yaml $d/configmap.yaml
    mv $d/04.yaml $d/route.yaml
done
```

Looking more closely at the secret, we see that it has a common field for all clusters, `ca.crt`

```bash
sdiff -w 100 mongo/overlays/east-*/secret.yaml

apiVersion: v1                                  apiVersion: v1
data:                                           data:
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS |   tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS
  tls.key: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRV |   tls.key: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRV
  tls.pw: ZWFzdC0xLXBhc3N3b3JkCg==            |   tls.pw: ZWFzdC0yLXBhc3N3b3JkCg==
  ca.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0     ca.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0
kind: Secret                                    kind: Secret
metadata:                                       metadata:
  name: qdr-internal-cert                         name: qdr-internal-cert
type: kubernetes.io/tls                         type: kubernetes.io/tls
```

Normally we would not bother over the duplication of a single ca certificate, but this is a good point to
demonstrate a useful feature of kustomize, the strategic merge patch. Start by making a copy of the secret in base:

```bash
cp mongo/overlays/east-1/secret.yaml mongo/base
```

Edit the base secret, removing the tls.crt, tls.key, and tls.pw lines which are unique per cluster.

Edit each overlay's secret.yaml, removing the ca.crt field which is common to all.

The mongo directory structure should now look as so:

```bash
mongo
├── base
│   ├── deployment.yaml
│   └── service.yaml
│   └── secret.yaml
└── overlays
    ├── east-1
    │   ├── configmap.yaml
    │   ├── route.yaml
    │   └── secret.yaml
    ├── east-2
    │   ├── configmap.yaml
    │   ├── route.yaml
    │   └── secret.yaml
    └── west-2
        ├── configmap.yaml
        ├── route.yaml
        └── secret.yaml
```

The next step is to add `kustomization.yaml` files to direct Argo CD to the content. Create the following under
`mongo/base/kustomization.yaml`

```yaml
resources:
- deployment.yaml
- service.yaml
- secret.yaml
```

In each of the overlays/cluster directories, create another `kustomization.yaml` with the following content; note the patchesStrategicMerge line which applies the overlay secret.yaml as a merge edit of the one in base:

```yaml
resources:
- ../../base
- configmap.yaml
- route.yaml
patchesStrategicMerge:
- secret.yaml
```

The final step before moving on to Argo CD is to commit all this code to the Git repo.

```bash
git add mongo
git commit -m 'Initial skupper resources'
git push
```

### Create Argo CD Application

First, make sure you have a matching command line interface for your server version of Argo CD and log in to the server

```bash
argocd login argocd-server-route-argocd.apps.example.com --insecure --grpc-web
```

Add the newly created repository to Argo CD.

```bash
argocd repo add https://github.com/your_org/your_repo

argocd app create --project default \
--name skuppman-db-c1 \
--repo https://github.com/your_org/your_repo \
--dest-namespace skuppman-db \
--revision master \
--sync-policy none \
--path mongo/overlays/east-1 \
--dest-server https://kubernetes.default.svc
```

Note the app we just added is set to the "none' sync policy which requires
manual intervention to sync. We will now try to sync the app:

```text
argocd app sync skuppman-db-c1

Name:               skuppman-db-c1
Project:            default
Server:             https://kubernetes.default.svc
Namespace:          skuppman-db
URL:                https://argocd-server-route-argocd.apps.east-1.example.com/applications/skuppman-db-c1
Repo:               git@github.com:RHsyseng/skupper.git
Target:             master
Path:               mongo/overlays/east-1
Sync Policy:        <none>
Sync Status:        OutOfSync from master (8e35460)
Health Status:      Missing

Operation:          Sync
Sync Revision:      8e35460a5211fba6901d3ab18c0cd96ba52a78f3
Phase:              Failed
Start:              2019-09-27 13:46:59 -0500 CDT
Finished:           2019-09-27 13:47:01 -0500 CDT
Duration:           2s
Message:            one or more objects failed to apply (dry run)

GROUP               KIND        NAMESPACE    NAME               STATUS     HEALTH   HOOK  MESSAGE
route.openshift.io  Route       skuppman-db  console            OutOfSync  Missing        kubectl failed exit status 1: error validating data: ValidationError(Route): missing required field "status" in com.github.openshift.api.route.v1.Route
                    ConfigMap   skuppman-db  qdr-config         OutOfSync  Missing
                    Secret      skuppman-db  qdr-internal-cert  OutOfSync  Missing
                    Service     skuppman-db  messaging          OutOfSync  Missing
extensions          Deployment  skuppman-db  qdrouterd          OutOfSync  Missing
```

From the output, no objects were able to sync and there was at least one error regarding the format of the Route object.
It turns out that the first problem is that the namespace into which Argo CD tries to create resources does not exist.
That should be easy to fix, use `oc` to create the namespace, export to yaml, and add it to the repo:

```bash
oc create ns skuppman-db -o yaml > mongo/base/namespace.yaml
echo "- namespace.yaml" >> mongo/base/kustomization.yaml
git add mongo/base
git commit -m 'added namespace'
```

To fix the Route object, it appears a status field is required. In testing, we found the following works best:

```yaml
status:
  ingress:
  - conditions:
    - status: 'True'
      type: Admitted
```

Add the above to the route objects, check them in to the repo and re-run the sync:

```bash
argocd app sync skuppman-db-c1

...
Sync Status:        OutOfSync from master (e3da7f7)
Health Status:      Healthy
```

The Healthy status is an improvement, but we are still getting OutOfSync errors. It turns out that some annotations
created by `oc` in the namespace do not always sync up. Edit the namespace.yaml to pare it down to a more basic
config by eliminating the extra fields not required to create a namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: skuppman-db
  selfLink: /api/v1/namespaces/skuppman-db
```

Commit and sync again, and there is only one object still refusing to sync, and
it's our Route again. To debug what is going on, use the argocd diff command:

```bash
argocd app diff skuppman-db-c1

===== route.openshift.io/Route skuppman-db/console ======
14c14
<   selfLink: /apis/route.openshift.io/v1/namespaces/skuppman-db/routes/console
---
>   selfLink: /apis/route.openshift.io/v1/namespaces/hello/routes/console
```

It looks like skoot assumed a namespace when creating its objects, let us remove the selfLink field from each route.

```bash
sed -i '/selfLink:/d' mongo/overlays/*/route.yaml
git add mongo/overlays
git commit -m 'removed selfLink lines'
git push
argocd app sync skuppman-db-c1
```

The application should be syncing cleanly and show as "Healthy" and "Synced". Before continuing, add applications
for the remaining two clusters:

```bash
argocd app create --project default \
--name skuppman-db-c2 \
--repo https://github.com/your_org/your_repo \
--dest-namespace skuppman-db \
--revision master \
--sync-policy none \
--path mongo/overlays/east-2 \
--dest-server https://api.east-2.example.com:6443 

argocd app create --project default \
--name skuppman-db-c3 \
--repo https://github.com/your_org/your_repo \
--dest-namespace skuppman-db \
--revision master \
--sync-policy none \
--path mongo/overlays/west-2 \
--dest-server https://api.west-2.example.com:6443 
```

On syncing the new clusters, we find one more issue, due to a bug in the Route object creation by skoot:

```text
argocd app sync skuppman-db-c3

<OUTPUT SKIPPED>

GROUP       KIND        NAMESPACE    NAME               STATUS     HEALTH   HOOK  MESSAGE
Route       skuppman-db  amqps              OutOfSync  Missing        Route "" not found
```

Looking at the working route in east-1, we see the apiVersion is
`route.openshift.io/v1` while the other clusters use `v1`. The latter, if
created with `oc` would work by automatically adjusting the actual resource
apiVersion, but as Argo CD is stricter, it rejects the resource, correctly
explaining that there is no Route resource in /v1 of the api. Change both
routes to the correct apiVersion, commit and push the git repo, then run
`argocd sync` again.

```bash
sed -i 's@v1@route.openshift.io/v1@' mongo/overlays/????-2/route.yaml
git commit -m 'Fixed apiVersion' mongo/overlays/*/route.yaml
git push
argocd app sync skuppman-db-c2
argocd app sync skuppman-db-c3
```

### Create Mongo Database

The next step is to create the MongoDB resources. For this, we borrow from the
[Skupper MongoDB Replica Set Demo](https://github.com/skupperproject/skupper-example-mongodb-replica-set)

```bash
for i in a b c
do
    curl -qO https://raw.githubusercontent.com/skupperproject/skupper-example-mongodb-replica-set/master/deployment-mongo-svc-${i}.yaml
done
```

Again, there is one file for each cluster, but as their differences include the resource names, we cannot use strategic merge patches to reuse code. Instead, copy each one into its relevant overlay directory:

```bash
mv deployment-mongo-svc-a.yaml mongo/overlays/east-1
mv deployment-mongo-svc-b.yaml mongo/overlays/east-2
mv deployment-mongo-svc-c.yaml mongo/overlays/west-2
```

Add the relevant line to each `kustomization.yaml` to start pushing the new file and sync.

Once there are mongodb pods running on all three clusters, there is some manual database administration
to be done to set up the replica set and to create the database and user for the pacman application.

To start, find the pod name of the first cluster's mongodb pod:

```bash
oc -n skuppman-db get pods

NAME                        READY   STATUS    RESTARTS   AGE
mongo-a-6d75dd6774-jlz6q    1/1     Running   0          118m
qdrouterd-fc44ccddc-qtthl   1/1     Running   1          2d23h
```

In this case, we want `mongo-a-6d75dd6774-jlz6q`. Now run an interactive mongo shell on that pod:

```bash
oc -n skuppman-db exec -ti mongo-a-6d75dd6774-jlz6q -- mongo
```

Paste in the following code

```js
rs.initiate( {
    _id : "rs0",
    members: [
        { _id: 0, host: "mongo-svc-a.skuppman-db:27017" },
        { _id: 1, host: "mongo-svc-b.skuppman-db:27017" },
        { _id: 2, host: "mongo-svc-c.skuppman-db:27017" }
    ]
})
```
