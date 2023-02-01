module "sqs" {
  source = "terraform-aws-modules/sqs/aws"

  name = "workload"

  tags = var.tags
}
