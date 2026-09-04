#!/bin/bash

set -e

# Start and enable Apache
sudo systemctl enable httpd
sudo systemctl start httpd

# Make database secret ARN available to PHP/Apache
sudo tee /etc/httpd/conf.d/backend-env.conf > /dev/null <<EOF
SetEnv DB_SECRET_ARN "${db_secret_arn}"
SetEnv AWS_REGION "${aws_region}"
EOF

# Restart Apache so the environment configuration is loaded
sudo systemctl restart httpd

# Create a simple health endpoint
echo "OK" | sudo tee /var/www/html/index.html > /dev/null

echo "Backend application initialized successfully."