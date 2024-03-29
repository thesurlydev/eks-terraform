variable "namespace" {
  description = "The name of the stack."
}

variable "environment" {
  description = "The name of your environment."
}

variable "region" {
  description = "The AWS region."
}

variable "vpc_id" {
  description = "The VPC the cluster should be created in"
}

variable "cluster_id" {
  description = "The ID of the cluster where the ingress controller should be attached"
}

variable "alb_ingress_controller_version" {
//  default = "v1.1.5"
  default = "v1.1.9"
}
