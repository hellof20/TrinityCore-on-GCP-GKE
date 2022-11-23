#!/bin/bash

echo "begin to deploy GKE using gcloud ..."
gcloud container clusters create $name \
    --cluster-version=1.23 \
    --no-enable-autoupgrade \
    --machine-type=e2-standard-4 \
    --num-nodes=1 \
    --zone $zone \
    --project=$project_id


kubectl apply -f wow-operator/crd/
kubectl apply -f wow-operator/wow-operator.yaml
sleep 60
kubectl apply -f wow/wow.yaml

waitTime=0
ready="ok"
until [[ $(k get wow -o jsonpath='{.items[].status.ready}') == 'ok' ]]; do
sleep 10;
waitTime=$(expr ${waitTime} + 10)
echo "waited ${waitTime} secconds for sdk to be ready ..."
if [ ${waitTime} -gt 300 ]; then
    ready="failed"
    echo "wait too long, failed."
    return 1
fi
done

if [[ ${ready} == "ok" ]];then
    kubectl get sdk
    kubectl get auth
else
    echo "deploy wow failed."    
fi