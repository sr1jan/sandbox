output "instance_id" {
  value       = aws_instance.sandbox.id
  description = "EC2 instance ID"
}

output "public_ip" {
  value       = aws_eip.sandbox.public_ip
  description = "Elastic IP (used for prod-replica SG allowlisting)"
}

output "tailnet_hostname" {
  value       = local.tailnet_hostname
  description = "Base hostname in the tailnet (e.g., dp-sandbox-<workspace>)"
}

output "vpc_id" {
  value       = aws_vpc.sandbox.id
  description = "Sandbox VPC ID"
}

output "iam_user_access_key_id" {
  value       = aws_iam_access_key.sandbox.id
  description = "AWS_ACCESS_KEY_ID for the sandbox IAM user — place in /etc/devbox/secrets on the VM"
  sensitive   = true
}

output "iam_user_secret_access_key" {
  value       = aws_iam_access_key.sandbox.secret
  description = "AWS_SECRET_ACCESS_KEY for the sandbox IAM user"
  sensitive   = true
}

output "ssm_break_glass_profile_name" {
  value       = aws_iam_instance_profile.ssm_break_glass.name
  description = "Name of the SSM-only instance profile to attach on demand for break-glass"
}

output "connection_instructions" {
  value = <<-EOT

    # Provisioning complete. Connect via Tailscale:
    tailscale ssh ubuntu@${local.tailnet_hostname}        # admin (sudo-capable)
    tailscale ssh agent@${local.tailnet_hostname}         # locked-down agent user

    # Break-glass via SSM (requires attaching the SSM profile first):
    aws ec2 associate-iam-instance-profile \\
      --instance-id ${aws_instance.sandbox.id} \\
      --iam-instance-profile Name=${aws_iam_instance_profile.ssm_break_glass.name}
    aws ssm start-session --target ${aws_instance.sandbox.id}
    # When done:
    aws ec2 disassociate-iam-instance-profile \\
      --association-id $(aws ec2 describe-iam-instance-profile-associations \\
        --filters Name=instance-id,Values=${aws_instance.sandbox.id} \\
        --query 'IamInstanceProfileAssociations[0].AssociationId' --output text)
  EOT
}
