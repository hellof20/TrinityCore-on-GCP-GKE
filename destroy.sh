#!/bin/bash

echo "begin to destroy..."
kubectl delete -f wow/wow.yaml

echo "deleting gke cluster"
gcloud container clusters delete $name \
    --zone $zone \
    --project=$project_id \
    --quiet

echo "complete"