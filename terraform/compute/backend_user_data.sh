#!/bin/bash

set -e

# Start and enable Apache
sudo systemctl enable httpd
sudo systemctl start httpd

# Create a simple health endpoint
echo "OK" | sudo tee /var/www/html/index.html > /dev/null

echo "Backend application initialized successfully."