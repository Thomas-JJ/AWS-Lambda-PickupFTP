resource "aws_lambda_layer_version" "paramiko_312" {
  layer_name          = "paramiko-py312"
  filename            = "${path.module}/paramiko-layer-312.zip"
  compatible_runtimes = ["python3.12"]
  description         = "Paramiko + deps for Python 3.12"
}
