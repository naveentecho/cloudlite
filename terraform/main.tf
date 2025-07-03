provider "aws" {
  region = "us-east-2"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "cloudlite-vpc" }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "cloudlite-igw" }
}

# Public Subnets
resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-2a"
  map_public_ip_on_launch = true
  tags = { Name = "cloudlite-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-2b"
  map_public_ip_on_launch = true
  tags = { Name = "cloudlite-public-2" }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "cloudlite-public-rt" }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main.id
  name   = "cloudlite-ec2-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["49.205.242.65/32"] # Replace with your IP (e.g., 203.0.113.0/32)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "cloudlite-ec2-sg" }
}

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "cloudlite-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "cloudlite-ec2-policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:Get*", "ecr:BatchGetImage", "ecr:Describe*"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:us-east-1:*:parameter/cloudlite/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "cloudlite-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 Instance
resource "aws_instance" "app" {
  ami                    = "ami-054d057aaa6f1aa39" # Amazon Linux 2 (update for your region)
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_1.id
  security_groups        = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install docker -y
              service docker start
              usermod -a -G docker ec2-user
              curl -L https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              EOF

  tags = { Name = "cloudlite-app" }
}

# S3 Bucket
resource "aws_s3_bucket" "static" {
  bucket = "cloudlite-static-${random_string.bucket_suffix.result}"
  tags   = { Name = "cloudlite-static" }
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_lifecycle_configuration" "static_lifecycle" {
  bucket = aws_s3_bucket.static.id
  rule {
    id     = "expire-objects"
    status = "Enabled"
    expiration { days = 7 }
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "sessions" {
  name           = "cloudlite-sessions"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "sessionId"
  attribute {
    name = "sessionId"
    type = "S"
  }
  tags = { Name = "cloudlite-sessions" }
}

# SSM Parameter Store
resource "aws_ssm_parameter" "app_config" {
  name  = "/cloudlite/app-config"
  type  = "String"
  value = "API_KEY=example_key"
}

# CloudWatch Alarm
resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "cloudlite-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Alert if CPU usage exceeds 70% for 10 minutes"
  dimensions = {
    InstanceId = aws_instance.app.id
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_policy" {
  bucket = aws_s3_bucket.static.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action = [
          "s3:GetBucketAcl",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.static.arn,
          "${aws_s3_bucket.static.arn}/AWSLogs/*"
        ]
      }
    ]
  })
}

# CloudTrail
resource "aws_cloudtrail" "trail" {
  name                          = "cloudlite-trail"
  s3_bucket_name                = aws_s3_bucket.static.id
  include_global_service_events = true
  is_multi_region_trail        = true
  enable_logging               = true
  depends_on                   = [aws_s3_bucket_policy.cloudtrail_policy]
}