**NOTICE: THESE MODULES ARE DEPRECATED AND NO LONGER MAINTAINED**


# terraform-kubernetes

Terraform modules to bootstrap a Kubernetes cluster on AWS using [`kops`](https://github.com/kubernetes/kops).

## cluster

Creates a full `kops` cluster specification yaml, including the required instance groups

### Available variables

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| bastion\_cidr | CIDR of the bastion host. This will be used to allow SSH access to kubernetes nodes. | string | - | yes |
| calico\_logseverity | Sets the logSeverityScreen setting for the Calico CNI. Defaults to 'warning' | string | `warning` | no |
| dns\_provider | DNS provider to use for the cluster. | string | `CoreDNS` | no |
| elb\_type | Whether to use an Internal or Public ELB in front of the master nodes | string | `Public` | no |
| environment | Environment where this node belongs to, will be the third part of the node name. Defaults to '' | string | `` | no |
| etcd\_encrypted\_volumes | Enable etcd volume encryption | string | `true` | no |
| etcd\_encryption\_kms\_key\_arn | Optional kms key arn to use to encrypt the etcd volumes | string | `` | no |
| etcd\_version | Which version of etcd do you want? | string | `` | no |
| extra\_master\_securitygroups | List of extra securitygroups that you want to attach to the master nodes | list | `<list>` | no |
| extra\_worker\_securitygroups | List of extra securitygroups that you want to attach to the worker nodes | list | `<list>` | no |
| k8s\_data\_bucket | S3 bucket to store the kops cluster description & state | string | - | yes |
| k8s\_image\_encryption | Enable k8s image encryption | string | `false` | no |
| k8s\_version | Kubernetes Version to deploy | string | - | yes |
| kms\_key\_arn | Optional kms key arn to use to encrypt the root volumes | string | `` | no |
| kube\_reserved\_cpu | CPU reserved for kubernetes system components | string | `100m` | no |
| kube\_reserved\_es | Ephemeral storage reserved for kubernetes system components | string | `1Gi` | no |
| kube\_reserved\_memory | Memory reserved for kubernetes system components | string | `150Mi` | no |
| kubelet\_eviction\_hard | Comma-delimited list of hard eviction expressions. | string | `memory.available<100Mi,nodefs.available<10%,nodefs.inodesFree<5%,imagefs.available<10%,imagefs.inodesFree<5%` | no |
| master\_instance\_type | - | string | `t2.medium` | no |
| master\_net\_number | The network number to start with for master subnet cidr calculation | string | - | yes |
| max\_amount\_workers | Maximum amount of workers | string | - | yes |
| min\_amount\_workers | Minimum amount of workers. Will default to the amount of AZs | string | `0` | no |
| name | Kubernetes Cluster Name | string | - | yes |
| nat\_gateway\_ids | List of NAT gateway ids to associate to the route tables created by kops. There must be one NAT gateway for each availability zone in the region. | list | - | yes |
| oidc\_issuer\_url | URL for the OIDC issuer (https://kubernetes.io/docs/admin/authentication/#openid-connect-tokens) | string | - | yes |
| spot\_price | Spot price you want to pay for your worker instances. By default this is empty and we will use on-demand instances | string | `` | no |
| system\_reserved\_cpu | CPU reserved for non-kubernetes components | string | `100m` | no |
| system\_reserved\_es | Ephemeral storage reserved for non-kubernetes components | string | `1Gi` | no |
| system\_reserved\_memory | Memory reserved for non-kubernetes components | string | `200Mi` | no |
| teleport\_server | Teleport auth server that this node will connect to, including the port number | string | - | yes |
| teleport\_token | Teleport auth token that this node will present to the auth server | string | - | yes |
| utility\_net\_number | The network number to start with for utility subnet cidr calculation | string | - | yes |
| vpc\_id | Deploy the Kubernetes cluster in this VPC | string | - | yes |
| worker\_instance\_type | - | string | `t2.medium` | no |
| worker\_net\_count | Amount of workers subnets to create (eg. to deploy single AZ). Defaults to the amount of AZ in the region | string | `0` | no |
| worker\_net\_number | The network number to start with for worker subnet cidr calculation | string | - | yes |

### Output

* None

### Example

```hcl
module "kops-aws" {
  source               = "github.com/skyscrapers/terraform-kubernetes//cluster?ref=0.4.0"
  name                 = "kops.internal.skyscrape.rs"
  environment          = "production"
  customer             = "customer"
  k8s_version          = "1.6.4"
  vpc_id               = "${module.customer_vpc.vpc_id}"
  k8s_data_bucket      = "kops-skyscrape-rs-state"
  master_instance_type = "m3.large"
  master_net_number    = "203"
  worker_instance_type = "c3.large"
  max_amount_workers   = "6"
  utility_net_number   = "13"
  oidc_issuer_url      = "https://signing.example.com/dex"
  teleport_token       = "78dwgfhjwdk"
  teleport_server      = "teleport.example.com:3025"
}
```

## base

**IMPORTANT:** If you're looking for the base terraform module, it has been moved to the [Kubernetes standard stack](https://github.com/skyscrapers/kubernetes-stack). The rest of this module will also be migrated soon.

## Usage

**Note**: [Refer to our documentation repo for the latest info on how to setup a cluster](https://github.com/skyscrapers/internal-documentation/tree/master/services/kubernetes/setup.md)

### Bootstrap

First include the `cluster` module in an existing or new Terraform stack ([example](#example)). Run Terraform and you will get a file `kops-cluster.yaml` in your current working folder.

If your TF setup was not correct and you need to regenerate the cluster spec and Terraform hints that all resources are up to date, just mark the cluster spec file resource as dirty:

```sh
terraform taint -module=kops-aws null_resource.kops_full_cluster-spec_file
```

Now rerun `terraform apply`.

Also install `kops`. See the section [Installing](https://github.com/kubernetes/kops#installing) of the `kops` readme file.

`kops` stores it's state in an S3 bucket. Point to the same S3 bucket as given in the Terraform setup:

```sh
export KOPS_STATE_STORE=s3://<s3-bucket-name>
```

*Replace `<s3-bucket-name>` with the name of the S3 bucket created with the `cluster` module*

To authenticate kops to AWS, you'll need to either set the credentials as environment variables, or use a profile name in your AWS config file with:

```sh
export AWS_PROFILE=MyProfile
```

### Create the cluster

*In the following examples, replace `<cluster-name>` with the correct cluster name that you're deploying. This is the name you set as `name` in the `cluster` module.*

Now create the cluster with its initial state on the S3 bucket:

```sh
kops create -f kops-cluster.yaml
```

Generate a new SSH key and register it in kops to use for the nodes admin user (remember to add the key to 1password so everyone can use it):

```sh
ssh-keygen -t rsa -b 4096 -C "<cluster-name>" -N "" -f <cluster-name>_key
kops create secret --name <cluster-name> sshpublickey admin -i ./<cluster-name>_key.pub
```

The name argument must match the cluster name you passed to the Terraform setup. Take a peek in the `kops-cluster.yaml` file if your forgot the name.

Kops calculates all the tasks it needs to execute. You can just see the output it *wants* to do by running the first command and you really execute it with the second command:

```sh
kops update cluster --name <cluster-name>
kops update cluster --name <cluster-name> --yes
```

Kops creates all the required AWS resources and eventually, your cluster should become available. If you ran `kops`, it will have saved the config to the API endpoint in the file `~/.kube/config`, ready to use for the Kubernetes CLI `kubectl`.

To test if your cluster came up correctly, run the command `kubectl get nodes` and you should see your master and worker nodes listed.

### Evolve your cluster

If you want to tweak the setup of your cluster, it is quite easy. Note however that while the process is easy, some of the changes could potentially break your cluster.

First, update the parameters you want to change in your Terraform setup.

Since we already have the cluster created, we must replace the old config with the new specification:

```sh
kops replace -f kops-cluster.yaml
```

If there are changes to AWS resources to be made, we can see and execute them by this pair of commands:

```sh
kops update cluster --name <cluster-name>
kops update cluster --name <cluster-name> --yes
```

If there are changes to an ASG, old existing nodes are not replaced automatically. To force this, you can view and execute which items it will upgrade in a rolling manner:

```sh
kops rolling-update cluster --name <cluster-name>
kops rolling-update cluster --name <cluster-name> --yes
```

Note that the `rolling-update` command also connects to the Kuberenetes API to monitor the liveliness of the complete system while the rolling upgrade is taking place.

If you made changes to one of the settings of your core Kuberenetes components (eg API), you will need to force the rolling update, you can use the following command.

```sh
kops rolling-update cluster --name <cluster-name> --instance-group <instance-group-name> --force --yes
```
