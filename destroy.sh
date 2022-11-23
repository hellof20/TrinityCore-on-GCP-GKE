#!/bin/bash

echo "begin to destroy..."
kubectl delete -f wow/wow.yaml
gcloud container clusters delete $name \
    --zone $zone \
    --project=$project_id