module "instance-sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "${var.project_name}-sg"
  description = "Security group for ${var.project_name}-service with custom ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      description = "all tcp"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

data "aws_iam_policy_document" "instance_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "sqs_policy" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:DeleteMessage",
      "sqs:ReceiveMessage"
    ]

    resources = [module.sqs.queue_arn]
  }
}

resource "aws_iam_role" "role" {
  name = "${var.project_name}_role"
  path = "/"

  assume_role_policy = data.aws_iam_policy_document.instance_assume_role_policy.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  tags = var.tags
}

resource "aws_iam_role_policy" "sqs_policy" {
  name   = "${var.project_name}_sqs_policy"
  role   = aws_iam_role.role.id
  policy = data.aws_iam_policy_document.sqs_policy.json
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.project_name}_instance_profile"
  role = aws_iam_role.role.name
}

locals {
  user_data = <<-USERDATA
    #!/bin/bash
    yum update -y
    yum install -y python38
    python3 -m pip install boto3
    
    wget https://gist.githubusercontent.com/gungoren/0d1e19e076607384bec3cf7c9a78b1f2/raw/6827804d0450cc8b6612ec2f4231e7159f881331/sqs_consumer.py

    QUEUE_URL="${module.sqs.queue_url}" AWS_DEFAULT_REGION="${var.region}" python3 sqs_consumer.py
  USERDATA
}

resource "aws_launch_template" "this" {
  name        = "${var.project_name}-launch_template"
  description = "Launch template ${var.project_name}"

  ebs_optimized = true
  image_id      = data.aws_ami.amazon_linux.id
  //key_name      = var.key_name
  user_data = base64encode(local.user_data)

  vpc_security_group_ids = [module.instance-sg.security_group_id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.profile.arn
  }

  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      encrypted             = true
      volume_size           = 20
    }
  }

  instance_type = var.instance_type

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

resource "aws_autoscaling_group" "this" {

  name = "${var.project_name}-asg"

  vpc_zone_identifier = module.vpc.private_subnets

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_size

  wait_for_capacity_timeout = 0

  health_check_type = "EC2"

  enabled_metrics = ["GroupInServiceInstances"]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      desired_capacity
    ]
  }
}


resource "null_resource" "create-rekognition-collection" {

  triggers = {
    asg_name    = aws_autoscaling_group.this.name
    config_file = templatefile("${path.module}/config.json.tpl", { asg_name = aws_autoscaling_group.this.name, queue_name = module.sqs.queue_name })
    region      = var.region
  }

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      tee /tmp/config.json <<CONFIG_JSON
      ${self.triggers.config_file}
      CONFIG_JSON
      aws autoscaling put-scaling-policy --policy-name sqs-backlog-target-tracking-scaling-policy \
        --auto-scaling-group-name ${self.triggers.asg_name} --policy-type TargetTrackingScaling \
        --target-tracking-configuration file:///tmp/config.json \
        --region ${self.triggers.region} 
    EOT
  }
}

/*
resource "aws_autoscaling_policy" "tracking_policy" {
  autoscaling_group_name = aws_autoscaling_group.this.name
  name                   = "${var.project_name}-tracking-scaling-policy"

  policy_type = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value     = 10

    customized_metric_specification {
      metrics {
        id = "m1"
        label = "Get the queue size (the number of messages waiting to be processed)"
        
        metric_stat {
          metric {
            namespace   = "AWS/SQS"
            metric_name = "ApproximateNumberOfMessagesVisible"
            dimensions {
              name  = "QueueName"
              value = module.sqs.queue_name
            }  
          }
          stat = "Sum"
        }
        return_data = false
      }

      metrics {
        id = "m2"
        label = "Get the group size (the number of InService instances)"
        metric_stat {
          metric {
            namespace   = "AWS/AutoScaling"
            metric_name = "GroupInServiceInstances"
            dimensions {
              name  = "AutoScalingGroupName"
              value = aws_autoscaling_group.this.name
            }
          }
          stat = "Average"
        }
        return_data = false
      }

      metrics {
        id          = "e1"
        expression  = "m1 / m2"
        label       = "Calculate the backlog per instance"
        return_data = true
      }
    }
  }
}*/

