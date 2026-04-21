#!/usr/bin/env bash
# Provision AWS S3 Files infrastructure for benchmarking.
#
# Creates: S3 bucket (versioned), IAM roles, S3 Files filesystem,
# mount target, security group rules. Installs efs-utils.
#
# Prerequisites:
#   - aws cli v2.34+ with s3files subcommand
#   - Authenticated AWS session (SSO or env vars)
#   - EC2 instance with instance profile (or will create one)
#
# Usage:
#   bash setup-s3files.sh --region us-west-2 --profile dcs
#
# Outputs the mount command when done. Teardown with:
#   bash setup-s3files.sh --teardown
set -euo pipefail

REGION="${REGION:-us-west-2}"
PROFILE="${AWS_PROFILE:-}"
BUCKET="dcs-s3files-bench"
FS_ROLE="s3files-bench-fs"
EC2_ROLE="s3files-bench-ec2"
PREFIX="s3files-bench"

PROF_ARG=""
[ -n "$PROFILE" ] && PROF_ARG="--profile $PROFILE"

aws_cmd() { aws $PROF_ARG --region "$REGION" "$@"; }

if [ "${1:-}" = "--teardown" ]; then
    echo "Tearing down S3 Files bench infrastructure..."
    FSID=$(aws_cmd s3files list-file-systems --query 'fileSystems[?bucket==`arn:aws:s3:::'"$BUCKET"'`].fileSystemId' --output text 2>/dev/null || true)
    if [ -n "$FSID" ] && [ "$FSID" != "None" ]; then
        # Delete mount targets
        for MT in $(aws_cmd s3files list-mount-targets --file-system-id "$FSID" --query 'mountTargets[].mountTargetId' --output text 2>/dev/null); do
            echo "  Deleting mount target $MT..."
            aws_cmd s3files delete-mount-target --mount-target-id "$MT" || true
        done
        sleep 10
        echo "  Deleting filesystem $FSID..."
        aws_cmd s3files delete-file-system --file-system-id "$FSID" || true
    fi

    # IAM cleanup
    aws_cmd iam delete-role-policy --role-name "$FS_ROLE" --policy-name s3files-bucket-access 2>/dev/null || true
    aws_cmd iam delete-role --role-name "$FS_ROLE" 2>/dev/null || true

    aws_cmd iam detach-role-policy --role-name "$EC2_ROLE" --policy-arn arn:aws:iam::aws:policy/AmazonS3FilesClientFullAccess 2>/dev/null || true
    aws_cmd iam delete-role-policy --role-name "$EC2_ROLE" --policy-name s3-bench-bucket-access 2>/dev/null || true
    IPID=$(aws_cmd iam list-instance-profiles-for-role --role-name "$EC2_ROLE" --query 'InstanceProfiles[0].InstanceProfileName' --output text 2>/dev/null || true)
    if [ -n "$IPID" ] && [ "$IPID" != "None" ]; then
        aws_cmd iam remove-role-from-instance-profile --instance-profile-name "$IPID" --role-name "$EC2_ROLE" 2>/dev/null || true
        aws_cmd iam delete-instance-profile --instance-profile-name "$IPID" 2>/dev/null || true
    fi
    aws_cmd iam delete-role --role-name "$EC2_ROLE" 2>/dev/null || true

    # S3 bucket (leave data, just report)
    echo "  Bucket $BUCKET left intact (delete manually if needed)."
    echo "Done."
    exit 0
fi

ACCOUNT=$(aws_cmd sts get-caller-identity --query 'Account' --output text)
echo "Account: $ACCOUNT, Region: $REGION"

# --- S3 bucket ---
if ! aws_cmd s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "Creating bucket $BUCKET..."
    aws_cmd s3api create-bucket --bucket "$BUCKET" \
        --create-bucket-configuration LocationConstraint="$REGION"
    aws_cmd s3api put-bucket-versioning --bucket "$BUCKET" \
        --versioning-configuration Status=Enabled
else
    echo "Bucket $BUCKET exists."
fi

# --- IAM: filesystem role ---
if ! aws_cmd iam get-role --role-name "$FS_ROLE" &>/dev/null; then
    echo "Creating filesystem IAM role..."
    aws_cmd iam create-role --role-name "$FS_ROLE" --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"elasticfilesystem.amazonaws.com"},
        "Action":"sts:AssumeRole",
        "Condition":{"StringEquals":{"aws:SourceAccount":"'"$ACCOUNT"'"},
          "ArnLike":{"aws:SourceArn":"arn:aws:s3files:'"$REGION"':'"$ACCOUNT"':file-system/*"}}}]
    }' >/dev/null
    aws_cmd iam put-role-policy --role-name "$FS_ROLE" --policy-name s3files-bucket-access --policy-document '{
      "Version":"2012-10-17",
      "Statement":[
        {"Effect":"Allow","Action":["s3:ListBucket","s3:ListBucketVersions"],
         "Resource":"arn:aws:s3:::'"$BUCKET"'",
         "Condition":{"StringEquals":{"aws:ResourceAccount":"'"$ACCOUNT"'"}}},
        {"Effect":"Allow","Action":["s3:AbortMultipartUpload","s3:DeleteObject","s3:DeleteObjectVersion",
          "s3:GetObject","s3:GetObjectVersion","s3:ListMultipartUploadParts","s3:PutObject"],
         "Resource":"arn:aws:s3:::'"$BUCKET"'/*",
         "Condition":{"StringEquals":{"aws:ResourceAccount":"'"$ACCOUNT"'"}}},
        {"Effect":"Allow","Action":["events:DeleteRule","events:DisableRule","events:EnableRule",
          "events:PutRule","events:PutTargets","events:RemoveTargets"],
         "Condition":{"StringEquals":{"events:ManagedBy":"elasticfilesystem.amazonaws.com"}},
         "Resource":["arn:aws:events:*:*:rule/DO-NOT-DELETE-S3-Files*"]},
        {"Effect":"Allow","Action":["events:DescribeRule","events:ListRuleNamesByTarget",
          "events:ListRules","events:ListTargetsByRule"],
         "Resource":["arn:aws:events:*:*:rule/*"]}
      ]
    }' >/dev/null
fi

# --- IAM: EC2 client role ---
if ! aws_cmd iam get-role --role-name "$EC2_ROLE" &>/dev/null; then
    echo "Creating EC2 IAM role..."
    aws_cmd iam create-role --role-name "$EC2_ROLE" --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }' >/dev/null
    aws_cmd iam attach-role-policy --role-name "$EC2_ROLE" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FilesClientFullAccess
    aws_cmd iam put-role-policy --role-name "$EC2_ROLE" --policy-name s3-bench-bucket-access --policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:GetObjectVersion","s3:ListBucket"],
        "Resource":["arn:aws:s3:::'"$BUCKET"'","arn:aws:s3:::'"$BUCKET"'/*"]}]
    }' >/dev/null
    if ! aws_cmd iam get-instance-profile --instance-profile-name "$EC2_ROLE" &>/dev/null; then
        aws_cmd iam create-instance-profile --instance-profile-name "$EC2_ROLE" >/dev/null
        sleep 5
        aws_cmd iam add-role-to-instance-profile --instance-profile-name "$EC2_ROLE" --role-name "$EC2_ROLE"
    fi
fi

# --- S3 Files filesystem ---
FSID=$(aws_cmd s3files list-file-systems --query 'fileSystems[?bucket==`arn:aws:s3:::'"$BUCKET"'`].fileSystemId | [0]' --output text 2>/dev/null || true)
if [ -z "$FSID" ] || [ "$FSID" = "None" ]; then
    echo "Creating S3 Files filesystem..."
    FSID=$(aws_cmd s3files create-file-system \
        --bucket "arn:aws:s3:::$BUCKET" \
        --role-arn "arn:aws:iam::${ACCOUNT}:role/$FS_ROLE" \
        --query 'fileSystemId' --output text)
    echo "  Waiting for filesystem $FSID..."
    for i in $(seq 1 60); do
        STATUS=$(aws_cmd s3files get-file-system --file-system-id "$FSID" --query 'status' --output text)
        [ "$STATUS" = "available" ] && break
        sleep 5
    done
fi
echo "Filesystem: $FSID"

# --- Mount target ---
# Detect instance subnet
INSTANCE_ID=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "")
if [ -n "$INSTANCE_ID" ]; then
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
    SUBNET=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/mac)/subnet-id)
    SG=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/security-groups | head -1)

    MT_COUNT=$(aws_cmd s3files list-mount-targets --file-system-id "$FSID" --query 'length(mountTargets)' --output text 2>/dev/null || echo "0")
    if [ "$MT_COUNT" = "0" ] || [ "$MT_COUNT" = "None" ]; then
        echo "Creating mount target in $SUBNET..."
        MTID=$(aws_cmd s3files create-mount-target \
            --file-system-id "$FSID" \
            --subnet-id "$SUBNET" \
            --query 'mountTargetId' --output text)
        echo "  Waiting for mount target $MTID (up to 5 min)..."
        for i in $(seq 1 60); do
            STATUS=$(aws_cmd s3files get-mount-target --mount-target-id "$MTID" --query 'status' --output text)
            [ "$STATUS" = "available" ] && break
            sleep 5
        done
    fi
fi

# --- Install efs-utils ---
if ! dpkg -l amazon-efs-utils &>/dev/null; then
    echo "Installing amazon-efs-utils..."
    curl -s https://amazon-efs-utils.aws.com/efs-utils-installer.sh | sh -s -- --install 2>&1 | tail -1
fi

echo ""
echo "========================================="
echo "Setup complete. Mount with:"
echo "  sudo mkdir -p /mnt/s3files"
echo "  sudo mount -t s3files ${FSID}:/ /mnt/s3files"
echo ""
echo "Then benchmark:"
echo "  bash bench/fs-bench.sh /mnt/s3files --baseline"
echo ""
echo "Teardown:"
echo "  bash bench/setup-s3files.sh --teardown"
echo "========================================="
