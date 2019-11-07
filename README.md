# Combining Skupper and GitOps using PacMan

[Skupper MongoDB Multi-Cluster RS](https://github.com/skupperproject/skupper-example-mongodb-replica-set)

[Argo CD GitOps](https://argoproj.github.io/argo-cd)

and

[Pacman](https://github.com/font/k8s-example-apps/blob/master/pacman-nodejs-app)

## Generating Skupper Configs

Start by following the instructions in the [Skupper MongoDB Multi-Cluster
ReplicaSet](https://github.com/skupperproject/skupper-example-mongodb-replica-set)
demo listed above through step four with a couple modifications.

### Managing Contexts

Rather than creating three separate terminals, merge your kubeconfigs [a good
guide can be found here](https://ahmet.im/blog/mastering-kubeconfig/). For
OpenShift 4 clusters, we find that the default admin user needs to be renamed
to match the cluster name before merging, we use sed:

    sed -i 's/admin/east1/g' east1/auth/kubeconfig
    sed -i 's/admin/east2/g' east2/auth/kubeconfig
    sed -i 's/admin/west2/g' west2/auth/kubeconfig

    export KUBECONFIG=east1/auth/kubeconfig:east2/auth/kubeconfig:west2/auth/kubeconfig
    oc config view --flatten > /path/to/composed-kubeconfig

    export KUBECONFIG=/path/to/composed-kubeconfig

Now when you want to operate on east1, use `--context=east1` for west2, `--context=west2` and so on.

The skupper commandline tool uses the -c flag for the same purpose.

### Namespaces

The next modification from the guide comes in our use of a separate namespace.
Since we are merging our kubeconfigs and do not want to use the `default`
namespace, each command needs to specify a namespace. Both `oc` and `skupper`
use the -n flag for this. Create namespaces in each cluster:

    for c in east1 east2 west2
    do
        oc --context=${c} create ns skuppman-db
    done

Now you can continue with the previously mentioned Skupper MongoDB ReplicaSet
guide or take a shortcut with [this script](skup.sh)

## Create ReplicaSet and Database

Once the skupper proxies are set up, execute an interactive session for `mongo`
on the mongo-svc-a pod on the first cluster:

    MONGOPOD=$(basename $(oc -n skuppman-db get pods -l application=mongo-a -o name))
    oc -n skuppman-db exec -ti $MONGOPOD -- mongoo

Paste in the following js code to create the replicaset using the namespaced mongo service names:

   rs.initiate( {
       _id : "rs0",
       members: [
          { _id: 0, host: "mongo-svc-a.skuppman-db:27017" },
          { _id: 1, host: "mongo-svc-b.skuppman-db:27017" },
          { _id: 2, host: "mongo-svc-c.skuppman-db:27017" }
       ]
    })
 
Wait a moment for the replica set to establish, and press enter to update the
prompt. It should now display:

    rs0:PRIMARY>

Create the pacman database with the following js:

    use pacman
    db.createUser(
      {
        user: "blinky",
        pwd: "pinky",
        roles: [ { role: "readWrite", db: "pacman" } ]
      }
    )
 
Exit the mongo command line with `exit`.

### Create Argo CD Application

First, make sure you have a matching command line interface for your server version of Argo CD and log in to the server

    argocd login argocd-server-route-argocd.apps.example.com --insecure --grpc-web

Add the newly created repository to Argo CD.

    argocd repo add https://github.com/your_org/your_repo

    argocd app create --project default \
    --name skuppman-db-c1 \
    --repo https://github.com/your_org/your_repo \
    --dest-namespace skuppman-db \
    --revision master \
    --sync-policy none \
    --path mongo/overlays/east-1 \
    --dest-server https://kubernetes.default.svc

Note the app we just added is set to the "none' sync policy which requires
manual intervention to sync. We will now try to sync the app:

```
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

    oc create ns skuppman-db -o yaml > mongo/base/namespace.yaml
    echo "- namespace.yaml" >> mongo/base/kustomization.yaml
    git add mongo/base
    git commit -m 'added namespace'

To fix the Route object, it appears a status field is required. In testing, we found the following works best:

```
status:
  ingress:
  - conditions:
    - status: 'True'
      type: Admitted
```

Add the above to the route objects, check them in to the repo and re-run the sync:

    argocd app sync skuppman-db-c1
    
    ...
    Sync Status:        OutOfSync from master (e3da7f7)
    Health Status:      Healthy

The Healthy status is an improvement, but we are still getting OutOfSync errors. It turns out that some annotations
created by `oc` in the namespace do not always sync up. Edit the namespace.yaml to pare it down to a more basic
config by eliminating the extra fields not required to create a namespace:

```
apiVersion: v1
kind: Namespace
metadata:
  name: skuppman-db
  selfLink: /api/v1/namespaces/skuppman-db
```

Commit and sync again, and there is only one object still refusing to sync, and
it's our Route again. To debug what is going on, use the argocd diff command:

```
argocd app diff skuppman-db-c1

===== route.openshift.io/Route skuppman-db/console ======
14c14
<   selfLink: /apis/route.openshift.io/v1/namespaces/skuppman-db/routes/console
---
>   selfLink: /apis/route.openshift.io/v1/namespaces/hello/routes/console
```

It looks like skoot assumed a namespace when creating its objects, let us remove the selfLink field from each route.

    sed -i '/selfLink:/d' mongo/overlays/*/route.yaml
    git add mongo/overlays
    git commit -m 'removed selfLink lines'
    git push
    argocd app sync skuppman-db-c1
    
The application should be syncing cleanly and show as "Healthy" and "Synced". Before continuing, add applications
for the remaining two clusters:

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

On syncing the new clusters, we find one more issue, due to a bug in the Route object creation by skoot:

    argocd app sync skuppman-db-c3

    <OUTPUT SKIPPED>

    GROUP       KIND        NAMESPACE    NAME               STATUS     HEALTH   HOOK  MESSAGE
    Route       skuppman-db  amqps              OutOfSync  Missing        Route "" not found

Looking at the working route in east-1, we see the apiVersion is
`route.openshift.io/v1` while the other clusters use `v1`. The latter, if
created with `oc` would work by automatically adjusting the actual resource
apiVersion, but as Argo CD is stricter, it rejects the resource, correctly
explaining that there is no Route resource in /v1 of the api. Change both
routes to the correct apiVersion, commit and push the git repo, then run
`argocd sync` again.

    sed -i 's@v1@route.openshift.io/v1@' mongo/overlays/????-2/route.yaml
    git commit -m 'Fixed apiVersion' mongo/overlays/*/route.yaml
    git push
    argocd app sync skuppman-db-c2
    argocd app sync skuppman-db-c3

### Create Mongo Database

The next step is to create the MongoDB resources. For this, we borrow from the
[Skupper MongoDB Replica Set Demo](https://github.com/skupperproject/skupper-example-mongodb-replica-set)

    for i in a b c
    do
        curl -qO https://raw.githubusercontent.com/skupperproject/skupper-example-mongodb-replica-set/master/deployment-mongo-svc-${i}.yaml
    done

Again, there is one file for each cluster, but as their differences include the resource names, we cannot use strategic merge patches to reuse code. Instead, copy each one into its relevant overlay directory:

    mv deployment-mongo-svc-a.yaml mongo/overlays/east-1
    mv deployment-mongo-svc-b.yaml mongo/overlays/east-2
    mv deployment-mongo-svc-c.yaml mongo/overlays/west-2

Add the relevant line to each `kustomization.yaml` to start pushing the new file and sync.

Once there are mongodb pods running on all three clusters, there is some manual database administration
to be done to set up the replica set and to create the database and user for the pacman application.

To start, find the pod name of the first cluster's mongodb pod:

    oc -n skuppman-db get pods
    
    NAME                        READY   STATUS    RESTARTS   AGE
    mongo-a-6d75dd6774-jlz6q    1/1     Running   0          118m
    qdrouterd-fc44ccddc-qtthl   1/1     Running   1          2d23h

In this case, we want `mongo-a-6d75dd6774-jlz6q`. Now run an interactive mongo shell on that pod:

    oc -n skuppman-db exec -ti mongo-a-6d75dd6774-jlz6q -- mongo

Paste in the following code

```
rs.initiate( {
    _id : "rs0",
    members: [
        { _id: 0, host: "mongo-svc-a.skuppman-db:27017" },
        { _id: 1, host: "mongo-svc-b.skuppman-db:27017" },
        { _id: 2, host: "mongo-svc-c.skuppman-db:27017" }
    ]
})
```

== Notes

  * DB did not come back cleanly after weekend shutdown.
  * Need app specific ignore for skupper.io annotations

