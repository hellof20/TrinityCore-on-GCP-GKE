#!/bin/bash

echo "begin to destroy..."

echo "get gke credential"
gcloud container clusters get-credentials $name \
    --zone $zone \
    --project=$project_id \
    --quiet

echo "deleting Wow ..."
kubectl delete -f wow/wow.yaml

echo "deleting GKE cluster"
gcloud container clusters delete $name \
    --zone $zone \
    --project=$project_id \
    --quiet

echo "complete"
