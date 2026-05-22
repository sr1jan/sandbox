# Sandbox IAM identity — one IAM user per sandbox VM. Holds whatever
# read-only AWS capabilities the sandbox needs (today: CloudWatch logs;
# add more attached policies as needs emerge — S3, SQS, Secrets Manager).
#
# Credentials are NOT attached as an instance profile. They go into
# /etc/devbox/secrets as AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY,
# consumed by `sudo run aws ...`.
#
# ADR 0002 constraint 3: hand-written policies only, no managed
# ReadOnlyAccess (which grants far more than the name implies).

resource "aws_iam_user" "sandbox" {
  name = "sandbox-${terraform.workspace}"
  path = "/sandbox/"

  tags = { Purpose = "Sandbox VM AWS identity - read-only" }
}

data "aws_iam_policy_document" "sandbox" {
  statement {
    sid    = "ReadLogs"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:DescribeQueries",
    ]
    # Scope to specific log groups if provided; else all (simpler for v1).
    resources = length(var.cloudwatch_log_group_arns) > 0 ? var.cloudwatch_log_group_arns : ["*"]
  }

  statement {
    sid    = "DenyAllWrites"
    effect = "Deny"
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DeleteLogGroup",
      "logs:DeleteLogStream",
      "logs:PutRetentionPolicy",
      "logs:PutMetricFilter",
      "logs:DeleteMetricFilter",
      "logs:TagResource",
      "logs:UntagResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "sandbox" {
  name   = "cloudwatch-readonly"
  user   = aws_iam_user.sandbox.name
  policy = data.aws_iam_policy_document.sandbox.json
}

data "aws_iam_policy_document" "s3_internal_upload" {
  statement {
    sid    = "PutInternalAssets"
    effect = "Allow"
    actions = [
      "s3:PutObject",
    ]
    resources = [
      "arn:aws:s3:::deepreel-assets/internal/*",
    ]
  }
}

resource "aws_iam_user_policy" "s3_internal_upload" {
  name   = "s3-internal-upload"
  user   = aws_iam_user.sandbox.name
  policy = data.aws_iam_policy_document.s3_internal_upload.json
}

data "aws_iam_policy_document" "ecs_exec" {
  statement {
    sid    = "ECSDiscover"
    effect = "Allow"
    actions = [
      "ecs:ListClusters",
      "ecs:ListTasks",
      "ecs:DescribeTasks",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECSExecute"
    effect = "Allow"
    actions = [
      "ecs:ExecuteCommand",
    ]
    resources = [
      "arn:aws:ecs:us-east-1:941377130901:cluster/dev-cluster",
      "arn:aws:ecs:us-east-1:941377130901:cluster/prod-cluster",
      "arn:aws:ecs:us-east-1:941377130901:task/dev-cluster/*",
      "arn:aws:ecs:us-east-1:941377130901:task/prod-cluster/*",
    ]
  }

  statement {
    sid    = "SSMSession"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecs_exec" {
  name   = "sandbox-ecs-exec-${terraform.workspace}"
  path   = "/sandbox/"
  policy = data.aws_iam_policy_document.ecs_exec.json
}

resource "aws_iam_user_policy_attachment" "ecs_exec" {
  user       = aws_iam_user.sandbox.name
  policy_arn = aws_iam_policy.ecs_exec.arn
}

data "aws_iam_policy_document" "ecs_deploy" {
  statement {
    sid    = "RegisterTaskDefinitions"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "PassTaskRoles"
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::941377130901:role/AmazonECSTaskRole",
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid    = "UpdateAndInspectServices"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:ListServices",
    ]
    resources = [
      "arn:aws:ecs:us-east-1:941377130901:cluster/dev-cluster",
      "arn:aws:ecs:us-east-1:941377130901:cluster/prod-cluster",
      "arn:aws:ecs:us-east-1:941377130901:service/dev-cluster/*-staging",
      "arn:aws:ecs:us-east-1:941377130901:service/dev-cluster/*-dev",
      "arn:aws:ecs:us-east-1:941377130901:service/prod-cluster/*-prod",
    ]
  }

  statement {
    sid    = "InspectTaskDefinitions"
    effect = "Allow"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
      "ecs:ListTaskDefinitionFamilies",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecs_deploy" {
  name   = "sandbox-ecs-deploy-${terraform.workspace}"
  path   = "/sandbox/"
  policy = data.aws_iam_policy_document.ecs_deploy.json
}

resource "aws_iam_user_policy_attachment" "ecs_deploy" {
  user       = aws_iam_user.sandbox.name
  policy_arn = aws_iam_policy.ecs_deploy.arn
}

data "aws_iam_policy_document" "ecr" {
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      "arn:aws:ecr:us-east-1:941377130901:repository/*",
    ]
  }

  statement {
    sid    = "ECRInspect"
    effect = "Allow"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]
    resources = [
      "arn:aws:ecr:us-east-1:941377130901:repository/*",
    ]
  }
}

resource "aws_iam_policy" "ecr" {
  name   = "sandbox-ecr-${terraform.workspace}"
  path   = "/sandbox/"
  policy = data.aws_iam_policy_document.ecr.json
}

resource "aws_iam_user_policy_attachment" "ecr" {
  user       = aws_iam_user.sandbox.name
  policy_arn = aws_iam_policy.ecr.arn
}

resource "aws_iam_access_key" "sandbox" {
  user = aws_iam_user.sandbox.name
}

# ---- SSM break-glass instance profile ----
# Created but NOT attached to the EC2 by default (ADR 0003). Operators
# attach on demand via `aws ec2 associate-iam-instance-profile` when
# Tailscale access is broken, then detach after the session.
resource "aws_iam_role" "ssm_break_glass" {
  name = "sandbox-ssm-break-glass-${terraform.workspace}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Purpose = "SSM break-glass - attach on demand per ADR 0003" }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_break_glass.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_break_glass" {
  name = "sandbox-ssm-break-glass-${terraform.workspace}"
  role = aws_iam_role.ssm_break_glass.name
}
