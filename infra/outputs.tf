output "instance_id" {
  value = aws_instance.server.id
}

output "public_ip" {
  value = aws_instance.server.public_ip
}

output "n8n_url" {
  value = "https://${var.domain}"
}

# Rendered configure script (contains no secrets: they are read on the server at run time).
output "configure_script_b64" {
  value = base64encode(local.configure_script)
}
