#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/ex-broadcaster-user-data.log) 2>&1

export AWS_REGION="${aws_region}"

ECR_REPOSITORY_URL="${ecr_repository_url}"
IMAGE_TAG="${image_tag}"
S3_BUCKET="${s3_bucket}"
S3_PREFIX="${s3_prefix}"

if ! command -v docker >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y docker.io
fi
systemctl enable docker
systemctl start docker

if ! command -v aws >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y unzip curl
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  (cd /tmp && unzip -q awscliv2.zip && ./aws/install)
fi

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REPOSITORY_URL"

IMAGE="$ECR_REPOSITORY_URL:$IMAGE_TAG"
docker pull "$IMAGE"

docker rm -f ex-broadcaster >/dev/null 2>&1 || true

docker run -d \
  --name ex-broadcaster \
  --restart unless-stopped \
  -p 1935:1935 \
  -p 127.0.0.1:8080:8080 \
  -e AWS_REGION="$AWS_REGION" \
  -e S3_BUCKET="$S3_BUCKET" \
  -e S3_PREFIX="$S3_PREFIX" \
  "$IMAGE"
