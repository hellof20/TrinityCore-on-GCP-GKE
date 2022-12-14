#!/bin/bash

echo "begin to deploy GKE using gcloud ..."

echo "creating GKE cluster ..."
gcloud container clusters create $name \
    --cluster-version=1.23 \
    --no-enable-autoupgrade \
    --machine-type=e2-standard-4 \
    --num-nodes=1 \
    --zone $zone \
    --project=$project_id
echo "GKE cluster done."

echo "Get GKE credential"
gcloud container clusters get-credentials $name \
    --zone $zone \
    --project=$project_id \
    --quiet

echo "Deploying WoW ..."
kubectl apply -f wow-operator/crd/
kubectl apply -f wow-operator/wow-operator.yaml

until [[ $(kubectl -n wow-operator get po -o jsonpath='{.items[].status.phase}') == 'Running' ]]; do
    sleep 10
done

kubectl apply -f wow/wow.yaml

waitTime=0
ready="ok"
until [[ $(kubectl get wow -o jsonpath='{.items[].status.ready}') == 'ok' ]]; do
sleep 10;
waitTime=$(expr ${waitTime} + 10)
echo "waited ${waitTime} secconds for sdk to be ready ..."
if [ ${waitTime} -gt 300 ]; then
    ready="failed"
    echo "wait too long, failed."
fi
done

if [[ ${ready} == "ok" ]];then
    kubectl get sdk
    kubectl get auth
    echo "deploy wow success."    
else
    echo "deploy wow failed."    
fi
