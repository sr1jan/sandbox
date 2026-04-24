# CloudWatch readonly IAM user (NOT attached as an instance profile —
# credentials go into /etc/devbox/secrets as AWS_ACCESS_KEY_ID /
# AWS_SECRET_ACCESS_KEY, consumed by `sudo run aws logs ...`).
#
# ADR 0002 constraint 3: hand-written policy only, no managed
# ReadOnlyAccess (which grants far more than the name implies).

resource "aws_iam_user" "cloudwatch_reader" {
  name = "sandbox-cloudwatch-reader-${terraform.workspace}"
  path = "/sandbox/"

  tags = { Purpose = "CloudWatch read-only access from sandbox VM" }
}

data "aws_iam_policy_document" "cloudwatch_reader" {
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

resource "aws_iam_user_policy" "cloudwatch_reader" {
  name   = "cloudwatch-readonly"
  user   = aws_iam_user.cloudwatch_reader.name
  policy = data.aws_iam_policy_document.cloudwatch_reader.json
}

resource "aws_iam_access_key" "cloudwatch_reader" {
  user = aws_iam_user.cloudwatch_reader.name
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

  tags = { Purpose = "SSM break-glass (attach on demand per ADR 0003)" }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_break_glass.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_break_glass" {
  name = "sandbox-ssm-break-glass-${terraform.workspace}"
  role = aws_iam_role.ssm_break_glass.name
}
