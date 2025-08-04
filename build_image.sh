#!/bin/bash
FLAGS=""

IMAGE_NAME="db-backups"
IMAGE_TAG="latest"
IMAGE_PATH="image"

IMAGE_BASE_NAME="debian"
IMAGE_BASE_TAG="latest"

# Parse command line arguments.
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --no-cache)
            FLAGS+="--no-cache "
            shift
            ;;
        --name=*)
            IMAGE_NAME="${key#*=}"
            shift
            ;;
        --tag=*)
            IMAGE_TAG="${key#*=}"
            shift
            ;;
        --path=*)
            IMAGE_PATH="${key#*=}"
            shift
            ;;
        --base-name=*)
            FLAGS+="--build-arg IMG_NAME=${key#*=} "
            shift
            ;;
        --base-tag=*)
            FLAGS += "--build-arg IMG_TAG=${key#*=} "
            shift
            ;;
        --help)
            echo "build_image.sh"
            echo -e "\t--name=<NAME> - The Docker image name. Defaults to 'db-backups'."
            echo -e "\t--tag=<TAG> - The Docker image tag. Defaults to latest."
            echo -e "\t--path=<PATH> - The path to the Docker image to build. Defaults to the 'image/' directory."
            echo -e "\t--base-name=<NAME> - The Docker image's base image to use. Defaults to 'debian'."
            echo -e "\t--base-tag=<TAG> - The Docker image's base image tag to use. Defaults to 'latest'."
            echo -e "\t--no-cache - Disables Docker build cache."
            exit 0
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo "Building Docker backups image..."

echo "Image Name: ${IMAGE_NAME}"
echo "Image Tag: ${IMAGE_TAG}"
echo "Image Path: ${IMAGE_PATH}/"
echo "Flags: ${FLAGS}"

docker build -t ${IMAGE_NAME}:${IMAGE_TAG} $FLAGS $IMAGE_PATH