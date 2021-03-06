locals {
  workspace_name   = terraform.workspace == "default" ? "" : "-${terraform.workspace}"
  module_name      = "bastion"
  res_prefix       = "${var.prefix}${local.workspace_name}"
  private_key_name = "ec2_id_rsa"
  default_tags = {
    Resprefix = local.res_prefix
    Prefix    = var.prefix
    Workspace = terraform.workspace
    Module    = local.module_name
    Terraform = "true"
  }
}

#
# SSH key generation
#

# We'll generate a SSH keypair with the tls_private_key resource
resource "tls_private_key" "ec2-ssh-key" {
  algorithm = "RSA"
}

# As the name suggests, a null_resource does not create a resoure, but use it to hook into creation time lifecycle for side effects.
# https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource
resource "null_resource" "ec2-save-ssh-key" {
  # We specify when the resource should be re-created, here, when the tls_private_key changes
  triggers = {
    key = tls_private_key.ec2-ssh-key.private_key_pem
  }

  # Every resource has a lifecycle, and we use the creation time lifecycle to write out the private key from Terraform state. 
  # (https://www.terraform.io/docs/provisioners/index.html#creation-time-provisioners)
  provisioner "local-exec" {
    command = <<EOF
      mkdir -p ${path.module}/.ssh
      echo "${tls_private_key.ec2-ssh-key.private_key_pem}" > ${path.root}/.ssh/${local.private_key_name}
      chmod 0600 ${path.root}/.ssh/${local.private_key_name}
EOF
  }
}

# We use the generated SSH keypair as the SSH key for the bastion instance
resource "aws_key_pair" "ec2-key-pair" {
  key_name   = "${var.prefix}${local.workspace_name}-ec2-key-pair"
  public_key = tls_private_key.ec2-ssh-key.public_key_openssh

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-ec2-key-pair"
  })
}

#
# IAM (Identity Access Management)
#

# Adding a role for the EC2 machine allows making AWS service APIs available via IAM policies
resource "aws_iam_role" "ec2-role" {
  name               = "${local.res_prefix}-ec2-iam-role"
  path               = "/"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-ec2-iam-role"
  })
}

resource "aws_iam_instance_profile" "ec2-iam-profile" {
  name = "${local.res_prefix}-ec2-iam-profile"
  role = aws_iam_role.ec2-role.name
}

resource "aws_iam_role_policy_attachment" "ssm-policy-attachment" {
  role       = aws_iam_role.ec2-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#
# Security groups
#

resource "aws_security_group" "bastion-subnet-sg" {
  name   = "${local.res_prefix}-bastion-subnet-sg"
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-bastion-subnet-sg"
  })
}

resource "aws_security_group_rule" "bastion-developer-workstation-ingress-rule" {
  description       = "Allow developers to access the bastion"
  security_group_id = aws_security_group.bastion-subnet-sg.id
  cidr_blocks       = tolist(var.developer_ips)
  from_port         = 22
  protocol          = "tcp"
  to_port           = 22
  type              = "ingress"
}

resource "aws_security_group_rule" "from-bastion-to-world-egress-rule" {
  description       = "Allow bastion to access world (e.g. for installing postgresql client etc)"
  security_group_id = aws_security_group.bastion-subnet-sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  protocol          = -1
  to_port           = 0
  type              = "egress"
}

resource "aws_security_group_rule" "from-bastion-to-database-ingress-rule" {
  description              = "Allow PostgreSQL connection from bastion"
  security_group_id        = data.terraform_remote_state.rds.outputs.rds_security_group_id
  source_security_group_id = aws_security_group.bastion-subnet-sg.id
  from_port                = 5432
  protocol                 = "tcp"
  to_port                  = 5432
  type                     = "ingress"
}

#
# The Bastion EC2 instance itself
#

resource "aws_instance" "bastion-ec2-instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  vpc_security_group_ids = [
  aws_security_group.bastion-subnet-sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2-iam-profile.name
  key_name             = aws_key_pair.ec2-key-pair.key_name
  tenancy              = var.tenancy_type

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-bastion"
  })
}

# Public IP address for the instance
resource "aws_eip" "ec2_eip" {
  instance = aws_instance.bastion-ec2-instance.id
  vpc      = true

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-ec2-eip"
  })
}
