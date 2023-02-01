locals {
  subnets = cidrsubnets("10.10.0.0/16", 4, 4, 4, 4)
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  private_subnets = slice(local.subnets, 0, 2)
  public_subnets  = slice(local.subnets, 2, 4)
  azs             = formatlist("${var.region}%s", ["a", "b"])

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = var.tags
}