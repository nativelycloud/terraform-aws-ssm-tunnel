#!/bin/sh -e

# Parse arguments
while [ $# -gt 0 ]; do
    case $1 in
        --assume-role-arn)
            AWS_ASSUME_ROLE_ARN=$2
            shift
            ;;
        --assume-role-session-name)
            AWS_ASSUME_ROLE_SESSION_NAME=$2
            shift
            ;;
        --assume-role-with-web-identity-role-arn)
            AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_ROLE_ARN=$2
            shift
            ;;
        --assume-role-with-web-identity-role-session-name)
            AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_ROLE_SESSION_NAME=$2
            shift
            ;;
        --assume-role-with-web-identity-token-env-var-name)
            AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_TOKEN_ENV_VAR_NAME=$2
            shift
            ;;
        --assume-role-with-web-identity-token-file-path)
            AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_TOKEN_FILE_PATH=$2
            shift
            ;;
        --aws-region)
            export AWS_REGION=$2
            shift
            ;;
        --aws-profile)
            export AWS_PROFILE=$2
            shift
            ;;
        --ecs-cluster-name)
            ECS_CLUSTER_NAME=$2
            shift
            ;;
        --ecs-service-name)
            ECS_SERVICE_NAME=$2
            shift
            ;;
        --ssm-document-name)
            SSM_DOCUMENT_NAME=$2
            shift
            ;;
        --target-host)
            TARGET_HOST=$2
            shift
            ;;
        --target-port)
            TARGET_PORT=$2
            shift
            ;;
        --local-port)
            LOCAL_PORT=$2
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
    shift
done

# Find parent Terraform process to know when to kill the tunnel process
UPPER_PID=$PPID
max_depth=10
while [ -z "$TERRAFORM_PID" ] && [ -n "$UPPER_PID" ] && [ $max_depth -gt 0 ]; do
    echo "UPPER_PID: $UPPER_PID" > /dev/stderr
    if [ -f "/proc/$UPPER_PID/comm" ]; then
        cat /proc/$UPPER_PID/comm > /dev/stderr
        if [ "$(cat /proc/$UPPER_PID/comm)" == "terraform" ]; then
            TERRAFORM_PID=$UPPER_PID
            break
        fi
    fi
    UPPER_PID=$(grep -oi 'PPID:\s[0-9]*' /proc/$UPPER_PID/status | cut -f2)
    max_depth=$((max_depth-1))
done
echo "TERRAFORM_PID: $TERRAFORM_PID" > /dev/stderr
if [ -z "$TERRAFORM_PID" ]; then
    echo "Failed to find parent terraform process" > /dev/stderr
    exit 1
fi

# AssumeRoleWithWebIdentity / AssumeRole
export_aws_temporary_credentials() {
    export AWS_ACCESS_KEY_ID=$(echo "$1" | cut -f1)
    export AWS_SECRET_ACCESS_KEY=$(echo "$1" | cut  -f2)
    export AWS_SESSION_TOKEN=$(echo "$1" | cut -f3)
}

if [ -n "$AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_ROLE_ARN" ]; then
    if [ -n "$AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_TOKEN_ENV_VAR_NAME" ]; then
        AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_TOKEN=$(printenv "$AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_TOKEN_ENV_VAR_NAME")
    elif [ -n "$AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_TOKEN_FILE_PATH" ]; then
        AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_TOKEN=$(cat "$AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_TOKEN_FILE_PATH")
    else
        echo "Either --assume-role-with-web-identity-token-env-var-name or --assume-role-with-web-identity-token-file-path must be provided"
        exit 1
    fi
    AWS_TEMPORARY_CREDENTIALS=$(aws sts assume-role-with-web-identity --role-arn "$AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_ROLE_ARN" --role-session-name "$AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_ROLE_SESSION_NAME" --web-identity-token "$AWS_ASSUME_ROLE_WITH_WEB_IDENTITY_TOKEN" --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
    export_aws_temporary_credentials "$AWS_TEMPORARY_CREDENTIALS"
fi

if [ -n "$AWS_ASSUME_ROLE_ARN" ]; then
    AWS_TEMPORARY_CREDENTIALS=$(aws sts assume-role --role-arn "$AWS_ASSUME_ROLE_ARN" --role-session-name "$AWS_ASSUME_ROLE_SESSION_NAME" --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
    export_aws_temporary_credentials "$AWS_TEMPORARY_CREDENTIALS"
fi

# Find the exact ECS container ID and runtime ID to ECS Exec into
ECS_TASK_ARN=$(aws ecs list-tasks --cluster "$ECS_CLUSTER_NAME" --service-name "$ECS_SERVICE_NAME" --desired-status RUNNING --query 'taskArns[0]' --output text)
echo "ECS_TASK_ARN: $ECS_TASK_ARN" > /dev/stderr

ECS_RUNTIME_ID=$(aws ecs describe-tasks --cluster "$ECS_CLUSTER_NAME" --tasks "$ECS_TASK_ARN"  --query 'tasks[0].containers[0].[runtimeId]' --output text)
echo "ECS_TASK_DETAILS: $ECS_TASK_DETAILS" > /dev/stderr

ECS_CONTAINER_ID=$(echo "$ECS_RUNTIME_ID" | cut -d'-' -f1)
echo "ECS_CONTAINER_ID: $ECS_CONTAINER_ID" > /dev/stderr

SSM_SESSION_TARGET="ecs:$ECS_CLUSTER_NAME"_"$ECS_CONTAINER_ID"_"$ECS_RUNTIME_ID"
echo "SSM_SESSION_TARGET: $SSM_SESSION_TARGET" > /dev/stderr

# Start SSM session
SSM_SESSION_PARAMETERS="{\"host\":[\"$TARGET_HOST\"],\"portNumber\":[\"$TARGET_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
echo "SSM_SESSION_PARAMETERS: $SSM_SESSION_PARAMETERS" > /dev/stderr

aws ssm start-session --target "$SSM_SESSION_TARGET" --document-name "$SSM_DOCUMENT_NAME" --parameters "$SSM_SESSION_PARAMETERS" &>/dev/null &
TUNNEL_PID=$!
echo "TUNNEL_PID: $TUNNEL_PID" > /dev/stderr

sleep 2
if ! kill -0 $TUNNEL_PID 2>/dev/null; then
    echo "Failed to start SSM session" > /dev/stderr
    exit 1
fi

# When Terraform exits, find the session manager plugin child process of the aws cli tunnel process and terminate it gracefully
sh -c "while kill -0 $TERRAFORM_PID 2>/dev/null; do sleep 1; done; kill -2 \`grep -il 'PPID:\s$TUNNEL_PID$' /proc/*/status | cut -d'/' -f3\`" &>/dev/null &
echo "SWEEPER_PID: $!" > /dev/stderr

#exit 1

# Return an empty JSON object for the Terraform data source to consume
echo "{}"