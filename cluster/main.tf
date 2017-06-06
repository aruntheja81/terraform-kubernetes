terraform {
	required_version = "> 0.8.0"
}

### NOTE: Do not change the layout of the template files or your will get unnecessary empty lines
###       in the generated output.

data "aws_vpc" "vpc_for_k8s" {
  id = "${var.vpc_id}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "kubernetes_ami" {
  most_recent = true
  # k8s-1.6-debian-jessie-amd64-hvm-ebs-2017-05-02
  name_regex = "^k8s-${element(split(".",var.k8s_version),0)}.${element(split(".",var.k8s_version),1)}-debian-jessie-amd64-hvm-ebs.*"
  owners = ["383156758163"]
}


#########################################################
# Subnets
#########################################################

# Private subnets to host the Kubernetes master nodes
data template_file "master-subnet-spec" {
  count = "3"
  template = "${file("${path.module}/../templates/kops-cluster-subnet.tpl.yaml")}"

  vars {
    name = "${element(formatlist("master-%s", data.aws_availability_zones.available.names),count.index)}"
    type = "Private"
    zone = "${element(data.aws_availability_zones.available.names, count.index)}"
    id   = ""
    cidr = "${cidrsubnet(data.aws_vpc.vpc_for_k8s.cidr_block,8,var.master_net_number+count.index)}"
  }
}

# Private subnets to host the Kubernetes worker nodes
data template_file "worker-subnet-spec" {
  count = "3"
  template = "${file("${path.module}/../templates/kops-cluster-subnet.tpl.yaml")}"

  vars {
    name = "${element(formatlist("worker-%s", data.aws_availability_zones.available.names), count.index)}"
    type = "Private"
    zone = "${element(data.aws_availability_zones.available.names, count.index)}"
    id   = ""
    cidr = "${cidrsubnet(data.aws_vpc.vpc_for_k8s.cidr_block,8,var.worker_net_number+count.index)}"
  }
}

# Utility subnets are public for ELB creation.
data template_file "utility-subnet-spec" {
  count = "3"
  template = "${file("${path.module}/../templates/kops-cluster-subnet.tpl.yaml")}"

  vars {
    name = "${element(formatlist("utility-%s", data.aws_availability_zones.available.names),count.index)}"
    type = "Utility"
    zone = "${element(data.aws_availability_zones.available.names, count.index)}"
    id   = ""
    cidr = "${cidrsubnet(data.aws_vpc.vpc_for_k8s.cidr_block,8,var.utility_net_number+count.index)}"
  }
}

#########################################################
# Instance Groups
#########################################################

data template_file "master-instancegroup-spec" {
  count = 3
  template = "${file("${path.module}/../templates/kops-instancegroup-master.tpl.yaml")}"

  vars {
    name           = "${element(formatlist("master-%s", data.aws_availability_zones.available.names),count.index)}"
    cluster-name   = "${var.name}"
    kubernetes_ami = "${data.aws_ami.kubernetes_ami.name}"
    subnets        = "${element(formatlist("  - master-%s", data.aws_availability_zones.available.names),count.index)}"
    instance_type  = "${var.master_instance_type}"
  }
}

data template_file "worker-instancegroup-spec" {
  template = "${file("${path.module}/../templates/kops-instancegroup-worker.tpl.yaml")}"

  vars {
    name          = "workers"
    cluster-name  = "${var.name}"
    kubernetes_ami = "${data.aws_ami.kubernetes_ami.name}"
    subnets       = "${join("\n", formatlist("  - worker-%s", data.aws_availability_zones.available.names))}"
    instance_type = "${var.worker_instance_type}"
    min           = "${length(data.aws_availability_zones.available.names)}"
    max           = "${var.max_amount_workers}"
  }

}

#########################################################
# Full Cluster
#########################################################

data template_file "cluster-etcd-member-spec" {
  template = "${file("${path.module}/../templates/kops-cluster-etcd-member.tpl.yaml")}"
  count = "3"

  vars {
    name    = "${element(formatlist("master-%s", data.aws_availability_zones.available.names),count.index)}"
    ig-name = "${element(formatlist("master-%s", data.aws_availability_zones.available.names),count.index)}"
  }
}

data template_file "cluster-spec" {
  template = "${file("${path.module}/../templates/kops-cluster.tpl.yaml")}"

  vars {
    name                  = "${var.name}"
    k8s_version           = "${var.k8s_version}"
    vpc_id                = "${data.aws_vpc.vpc_for_k8s.id}"
    vpc_cidr              = "${data.aws_vpc.vpc_for_k8s.cidr_block}"
    elb_type              = "${var.elb_type}"
    k8s_data_bucket       = "${var.k8s_data_bucket}"
    oidc_issuer_url       = "${var.oidc_issuer_url}"
    etcd_members_main     = "${join("\n",data.template_file.cluster-etcd-member-spec.*.rendered)}"
    etcd_members_events   = "${join("\n",data.template_file.cluster-etcd-member-spec.*.rendered)}"
    master_subnets        = "${join("\n",data.template_file.master-subnet-spec.*.rendered)}"
    worker_subnets        = "${join("\n",data.template_file.worker-subnet-spec.*.rendered)}"
    utility_subnets       = "${join("\n",data.template_file.utility-subnet-spec.*.rendered)}"
    master_instance_group = "${join("\n",data.template_file.master-instancegroup-spec.*.rendered)}"
    worker_instance_group = "${data.template_file.worker-instancegroup-spec.rendered}"
  }
}


resource "null_resource" "kops_full_cluster-spec_file" {

  provisioner "local-exec" {
    command = <<-EOC
      tee kops-cluster.yaml <<EOF
      ${data.template_file.cluster-spec.rendered}
      EOF
      EOC
  }

}
