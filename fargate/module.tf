terraform {
  required_version = "~>0.14"
  backend "s3" {
    bucket  = "${var.namespace}-tf-state-${var.region}"
    key     = "${var.environment}/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.region
}

resource "aws_iam_role_policy_attachment" "AmazonEKSFargatePodExecutionRolePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_pod_execution_role.name
}

resource "aws_iam_role" "fargate_pod_execution_role" {
  name                  = "${var.namespace}-eks-fargate-pod-execution-role"
  force_detach_policies = true

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "eks.amazonaws.com",
          "eks-fargate-pods.amazonaws.com"
          ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_eks_fargate_profile" "main" {
  cluster_name           = var.eks_cluster_name
  fargate_profile_name   = var.fargate_profile_name
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_role.arn
  subnet_ids             = var.private_subnets.*.id

  selector {
    namespace = "default"
  }

  timeouts {
    create = "30m"
    delete = "60m"
  }
}

resource "aws_eks_fargate_profile" "coredns" {
  cluster_name           = var.eks_cluster_name
  fargate_profile_name   = "coredns"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_role.arn
  subnet_ids             = var.private_subnets.*.id
  selector {
    namespace = "kube-system"
    labels = {
      k8s-app = "kube-dns"
    }
  }
}

data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.eks_cluster_name
}

// The following is a hack to run Fargate only.
// Stolen from https://github.com/hashicorp/terraform-provider-kubernetes/issues/723#issuecomment-679423792
resource "null_resource" "k8s_patcher" {
  depends_on = [ aws_eks_fargate_profile.coredns ]
  triggers = {
    // fire any time the cluster is update in a way that changes its endpoint or auth
    endpoint = var.eks_cluster_endpoint
    ca_crt   = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token    = data.aws_eks_cluster_auth.cluster.token
  }
  provisioner "local-exec" {
    command = <<EOH
cat >/tmp/ca.crt <<EOF
${base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)}
EOF
apk --no-cache add curl && \
curl -o aws-iam-authenticator https://amazon-eks.s3.us-west-2.amazonaws.com/1.18.9/2020-11-02/bin/linux/amd64/aws-iam-authenticator && chmod +x ./aws-iam-authenticator && \
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x ./kubectl && \
mkdir -p $HOME/bin && mv ./aws-iam-authenticator $HOME/bin/ && export PATH=$PATH:$HOME/bin && \
./kubectl \
  --server="${var.eks_cluster_endpoint}" \
  --certificate_authority=/tmp/ca.crt \
  --token="${data.aws_eks_cluster_auth.cluster.token}" \
  patch deployment coredns \
  -n kube-system --type json \
  -p='[{"op": "remove", "path": "/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]'
EOH
  }
}