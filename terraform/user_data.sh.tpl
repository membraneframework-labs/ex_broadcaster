#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/ex-broadcaster-user-data.log) 2>&1

export AWS_REGION="${aws_region}"
export DEBIAN_FRONTEND=noninteractive

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

GPU_DOCKER_ARGS=()

apt-get update -y
apt-get install -y linux-headers-aws ubuntu-drivers-common gcc-12 nvidia-driver-595 nvidia-utils-595

if [ "${gpu_enabled}" = "true" ]; then
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    apt-get update -y
    # linux-headers-aws (not linux-headers-$(uname -r)) tracks whatever
    # kernel linux-aws actually installs, so the dkms build below always
    # gets headers matching the running AWS-flavored kernel.
    apt-get install -y linux-headers-aws ubuntu-drivers-common gcc-12 nvidia-driver-595 nvidia-utils-595
    # The running kernel is built with gcc-12, but build-essential's default
    # /usr/bin/gcc is gcc-11 - the kernel Makefile unconditionally passes a
    # gcc-12-only flag (-ftrivial-auto-var-init=zero), so any dkms module
    # build fails unless CC is pointed at gcc-12 explicitly.
    export CC=/usr/bin/gcc-12
    # `ubuntu-drivers install --gpgpu` (not a hardcoded nvidia-driver-*-server
    # package) picks a driver branch Canonical has validated against the
    # kernel that's actually running, so this doesn't go stale/break dkms
    # every time the AMI rolls onto a newer kernel.
#    if ! ubuntu-drivers install --gpgpu; then
#      echo "FATAL: ubuntu-drivers install --gpgpu (nvidia driver/dkms build) failed for" \
#        "kernel $(uname -r). See /var/lib/dkms/*/*/build/make.log on this instance" \
#        "(before it gets terminated by the ASG health check) for the dkms failure detail." >&2
#      exit 1
#    fi
    unset CC
    # --gpgpu installs the headless/no-dkms package set, which omits
    # nvidia-smi (it only ships in nvidia-utils-<branch>-server) - the
    # cloudwatch agent's nvidia_smi input plugin needs that binary to exist.
    # It also omits libnvidia-gl-<branch>-server, which ships the Vulkan/GL
    # driver libraries and /usr/share/vulkan/icd.d/nvidia_icd.json - without
    # it, neither the host nor any container has anything for the Vulkan
    # loader to find, regardless of NVIDIA_DRIVER_CAPABILITIES.
    DRIVER_BRANCH=$(modinfo -F version nvidia | cut -d. -f1)
    apt-get install -y "nvidia-utils-$DRIVER_BRANCH-server" "libnvidia-gl-$DRIVER_BRANCH-server"
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

  # NVIDIA_DRIVER_CAPABILITIES defaults to "utility,compute" for containers,
  # which excludes Vulkan/GL - without "graphics" here vkCreateInstance fails
  # with ERROR_INCOMPATIBLE_DRIVER even though the host's own vulkaninfo works.
  GPU_DOCKER_ARGS=(--gpus all -e NVIDIA_DRIVER_CAPABILITIES=all --runtime=nvidia )
  # The container toolkit mounts the driver's .so files into the container via
  # ldcache but doesn't pick up the Vulkan ICD json descriptors, so the Vulkan
  # loader inside the container has no ICD to load even once libGLX_nvidia.so
  # itself is present - bind-mount them from the host explicitly instead.
  for icd_file in /usr/share/vulkan/icd.d/nvidia_icd.json /usr/share/vulkansc/icd.d/nvidia_icd_vksc.json; do
    if [ -f "$icd_file" ]; then
      GPU_DOCKER_ARGS+=(-v "$icd_file:$icd_file:ro")
    fi
  done
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

if ! aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REPOSITORY_URL"; then
  echo "FATAL: docker login to ECR repository $ECR_REPOSITORY_URL (region $AWS_REGION) failed." \
    "Check that this instance's IAM role still has AmazonEC2ContainerRegistryReadOnly and that" \
    "NAT/network egress to ECR is up (this instance runs in a private subnet)." >&2
  exit 1
fi

IMAGE="$ECR_REPOSITORY_URL:$IMAGE_TAG"
if ! docker pull "$IMAGE"; then
  echo "FATAL: docker pull failed for image $IMAGE." \
    "Check that tag '$IMAGE_TAG' was actually pushed to $ECR_REPOSITORY_URL — a missing/typo'd" \
    "app_image_tag is the most common cause; this is otherwise the same login/network failure" \
    "as above surfacing at pull time instead." >&2
  exit 1
fi

docker rm -f ex-broadcaster >/dev/null 2>&1 || true

docker run -d \
  --name ex-broadcaster \
  --restart unless-stopped \
  "$${GPU_DOCKER_ARGS[@]}" \
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
