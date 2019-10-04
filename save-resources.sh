#!/bin/bash
OVERLAYS=mongo/overlays
BASE=mongo/base
NAMESPACE=skuppman-db

for c in east1 east2 west2
do
    for res in $(oc --context $c -n $NAMESPACE \
        get deployments,sa,secrets \
        -o name | grep -v -E \
        '(builder|default|deployer|dockercfg|token)' )
    do
        file="${OVERLAYS}/${c}/$(dirname $res)-$(basename $res)"
        oc --context $c -n $NAMESPACE \
            get $res -o yaml --export > $file
    done
done
for res in $(oc --context east1 -n $NAMESPACE \
    get roles,rolebindings \
    -o name | grep -v -E \
    '(system|token)' )
do
    file="${BASE}/$(dirname $res)-$(basename $res)"
    oc --context east1 -n $NAMESPACE \
        get $res -o yaml > $file
done

# Remove lines which create false differences
sed -i -e '/^\s*creationTimestamp:/d' \
       -e '/^\s*resourceVersion:/d' \
       -e '/^\s*selfLink:/d' \
       -e '/^\s*namespace:/d' \
       -e '/^  uid:/d' \
       mongo/overlays/*/* \
       mongo/base/role*
