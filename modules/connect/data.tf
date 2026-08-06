data "aws_connect_instance" "main" {
  instance_alias = var.aws_connect_alias
}

data "aws_connect_hours_of_operation" "basic" {
  name        = var.hours_of_operation_name
  instance_id = data.aws_connect_instance.main.id
}
