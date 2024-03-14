terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "sinno-directive-tf-state"   # REPLACE WITH YOUR BUCKET NAME
    key            = "tf-infra/terraform.tfstate" # TODO 后续每个terraform项目都不一样
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-state-locking"
    encrypt        = true
  }
}


provider "aws" {
  region = "ap-southeast-1"
}

data "archive_file" "nestjs_app" {
  type = "zip"

  source_dir  = "${path.module}/../dist"
  output_path = "${path.module}/../nestapp.zip"
}

resource "aws_s3_object" "nest_app_zip" {
  bucket = "sinno-code-bucket"

  key = "nestapp.zip"

  source = data.archive_file.nestjs_app.output_path
  etag   = filemd5(data.archive_file.nestjs_app.output_path)
}

resource "aws_lambda_function" "nest-app" {
  function_name = "nestapp"

  s3_bucket = "sinno-code-bucket"
  s3_key    = aws_s3_object.nest_app_zip.key

  runtime          = "nodejs20.x"
  handler          = "main.handler"
  source_code_hash = data.archive_file.nestjs_app.output_base64sha256

  role = "arn:aws:iam::053346009561:role/ts_lambda-role"
}

resource "aws_cloudwatch_log_group" "hello_py" {
  name = "/aws/lambda/${aws_lambda_function.nest-app.function_name}"

  retention_in_days = 7
}

resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "dev"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "hello_world" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.nest-app.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "hello_world" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.hello_world.id}"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nest-app.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}
