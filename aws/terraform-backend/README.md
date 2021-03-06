# terraform-backend

Module for creating resources for [Terraform backend state](https://www.terraform.io/docs/backends/index.html) , with Terraform itself :). State is stored in S3, with concurrent operations prevented by a lock in DynamoDB table.

## Usage

You need to set up the environment variables. In this directory, run:

```bash
source ../tools/aws-envs.sh
```

First initialize the local backend:

```bash
terraform init
# You will see output like:
Initializing the backend...

Initializing provider plugins...
- Using previously-installed hashicorp/aws v3.11.0

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

Check plan with:

```bash
terraform plan
# You will see output like:
Refreshing Terraform state in-memory prior to plan...
The refreshed state will be used to calculate this plan, but will not be
persisted to local or remote state storage.
------------------------------------------------------------------------
An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create
Terraform will perform the following actions:
  # aws_dynamodb_table.terraform will be created
  + resource "aws_dynamodb_table" "terraform" {
      + arn              = (known after apply)
...
Plan: 6 to add, 0 to change, 0 to destroy.
```

Apply changes:

```bash
terraform apply
# You will see output like:
An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create
Terraform will perform the following actions:
...
```

Finally Terraform asks whether to apply the changes, reply: `yes`.

Terraform start to create the resources, you will see output like:

```
aws_kms_key.terraform: Creating...
aws_dynamodb_table.terraform: Creating...
aws_s3_bucket.terraform: Creating...
...
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.
...
Outputs:
dynamodb_table = <PREFIX-YOU-USED>-terraform
kms_key_id = arn:aws:kms:eu-west-1:<SOME-STRING>
state_bucket = <PREFIX-YOU-USED>-terraform
```

Now you can list the S3 buckets and DynamoDB tables in your account - you should see a bucket and table with your prefix:

```bash
aws s3 ls
aws dynamodb list-tables
```

Commit `terraform.tfstate` file, which is the local backend state file, into version control. The rationale is that this state file can be shared between developers.

```bash
git add terraform.tfstate
git commit -m "Terraform backend created"
```
