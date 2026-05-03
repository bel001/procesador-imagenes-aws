output "api_gateway_url" {
  description = "La URL pública del API Gateway para enviar la petición POST"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}