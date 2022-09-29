#!/bin/bash
set -e

# Since CONTAINER_REGISTRY is locked down, we can't directly build container image
# on it. So we use a temporary ACR to build the image and then copy over the image
# to the CONTAINTER_REGISTRY

echo 'Create temp ACR'
az acr create --resource-group $RESOURCE_GROUP -n $TEMP_CONTAINER_REGISTRY --sku Basic

for (( i=1 ; i<=$NUMBER_OF_IMAGES ; i++ ))
do
    IMAGE_TAG_VAR=IMAGE_TAG_$i
    DOCKER_FILE_VAR=DOCKER_FILE_$i
    SOURCE_LOCATION_VAR=SOURCE_LOCATION_$i

    IMAGE_TAG=${!IMAGE_TAG_VAR}
    DOCKER_FILE=${!DOCKER_FILE_VAR}
    SOURCE_LOCATION=${!SOURCE_LOCATION_VAR}

    # script to build a container image using ACR
    echo 'Build image on temp ACR for $IMAGE_TAG'
    az acr build --resource-group $RESOURCE_GROUP --registry $TEMP_CONTAINER_REGISTRY --image $IMAGE_TAG -f $DOCKER_FILE $SOURCE_LOCATION

    echo 'Import image from temp ACR'
    az acr import --force --resource-group $RESOURCE_GROUP --name $CONTAINER_REGISTRY --source "$TEMP_CONTAINER_REGISTRY.azurecr.io/$IMAGE_TAG" --image $IMAGE_TAG
done

echo 'Delete temp ACR'
az acr delete --resource-group $RESOURCE_GROUP --name $TEMP_CONTAINER_REGISTRY --yes