
`
terraform init
`

Create Plan
`
terraform apply
`

Destroy EC2 instances
`
terraform destroy
`

List resources in state
`
terraform state list
`

to get external resource, example EC2 below
`
terraform import aws_instance.test_external_ec2 <instance_id>
`

`
terraform state show aws_instance.test_external_ec2
`
gives details on the instance if you want to read the details on the external resource
