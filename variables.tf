variable "tags" {
  default = {
    Owner       = "Mehmet"
    Environment = "Dev"
  }
}

variable "region" {
  default = "us-east-2"
}

variable "project_name" {
  default = "workload"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "min_size" {
  default = 0
}

variable "max_size" {
  default = 10
}

variable "desired_size" {
  default = 0
}

variable "vpc_cidr" {
  default = "10.10.0.0/16"
}

variable "target_value" {
  default = 10
}