#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/ex-broadcaster-user-data.log) 2>&1

export AWS_REGION="${aws_region}"

ECR_REPOSITORY_URL="${ecr_repository_url}"
IMAGE_TAG="${image_tag}"
S3_BUCKET="${s3_bucket}"
S3_PREFIX="${s3_prefix}"
APP_LOG_GROUP="${app_log_group}"

IMDS_TOKEN=$(curl -fsSL -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -fsSL -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  "http://169.254.169.254/latest/meta-data/instance-id")

if ! command -v docker >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y docker.io
fi
systemctl enable docker
systemctl start docker

if ! command -v nvidia-smi >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y linux-headers-$(uname -r)
  curl -fsSL "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb" -o /tmp/cuda-keyring.deb
  dpkg -i /tmp/cuda-keyring.deb
  apt-get update -y
  apt-get install -y nvidia-driver-535-server
fi

if ! command -v nvidia-ctk >/dev/null 2>&1; then
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list
  apt-get update -y
  apt-get install -y nvidia-container-toolkit
  nvidia-ctk runtime configure --runtime=docker
  systemctl restart docker
fi

if ! command -v amazon-cloudwatch-agent-ctl >/dev/null 2>&1; then
  curl -fsSL "https://s3.$AWS_REGION.amazonaws.com/amazoncloudwatch-agent-$AWS_REGION/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb" \
    -o /tmp/amazon-cloudwatch-agent.deb
  dpkg -i /tmp/amazon-cloudwatch-agent.deb
fi

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
${cloudwatch_agent_config}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

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
  --gpus all \
  --log-driver=awslogs \
  --log-opt awslogs-region="$AWS_REGION" \
  --log-opt awslogs-group="$APP_LOG_GROUP" \
  --log-opt awslogs-stream="$INSTANCE_ID" \
  --log-opt awslogs-create-group=false \
  -p 1935:1935 \
  -p 127.0.0.1:8080:8080 \
  -e AWS_REGION="$AWS_REGION" \
  -e S3_BUCKET="$S3_BUCKET" \
  -e S3_PREFIX="$S3_PREFIX" \
  "$IMAGE"
