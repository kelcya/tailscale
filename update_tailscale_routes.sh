#!/bin/bash
#
# Update tailscale routes by pulling routes from aws secrets
# There exist a secret that houses the following key values: internal_routes, external_routes, authkey, apikey

# AWS secret manager secret
aws_secret_id=<aws_secret_name>

# Internal routes
internal_routes=$(aws secretsmanager get-secret-value --region us-east-1 --secret-id $aws_secret_id --query SecretString --output text | jq -r .internal_routes)

# External routes
external_routes+=$(aws secretsmanager get-secret-value --region us-east-1 --secret-id $aws_secret_id --query SecretString --output text | jq -r .external_routes)

# If there are no external routes, just advertise internal routes.
if [ -z "$external_routes" ]; then
  advertise_routes=("${internal_routes}")
else
  # Join internal and external routes
  advertise_routes=("${internal_routes},${external_routes}")
fi

# Get the tailscale keys
authkey=$(aws secretsmanager get-secret-value --region us-east-1 --secret-id $aws_secret_id --query SecretString --output text | jq -r .authkey)
apikey=$(aws secretsmanager get-secret-value --region us-east-1 --secret-id $aws_secret_id --query SecretString --output text | jq -r .apikey)

# Advertise the routes on this subnet router
tailscale up --login-server https://login.us.tailscale.com --authkey="$authkey" --advertise-routes="$advertise_routes"

# Get the node ID for the current subnet router
nodeId=$(curl -s "https://api.us.tailscale.com/api/v2/tailnet/cedar.com/devices" -u "$apikey:" | jq .devices | jq -r ".[] | select(.hostname==\"$(hostname)\") | .nodeId")

# Get the advertised routes
advertisedRoutes=$(curl -s "https://api.us.tailscale.com/api/v2/device/$nodeId/routes" -u "$apikey:" | jq .advertisedRoutes)

# Remove old routes.json while keeping a copy
mv routes.json routes.json.old

# Output the route json data to a file because I cannot figure how to pass the variable, sparing my sanity.
cat <<EOF >routes.json
{"routes": ${advertisedRoutes}}
EOF

# Safeguard - If the number of routes removed is greater than 5, exit.
if [ "$(grep -cFvf routes.json routes.json.old)" -gt 5 ]; then
  echo "Too many routes removed (>5). To override, comment out the exit 1 below and run again. Do not forget to uncomment!"
  exit 1
fi

# Enable the routes
echo "Enabling all advertised routes now. Advertised and enabled routes will be shown below."
echo ""
echo ""
curl -s "https://api.us.tailscale.com/api/v2/device/$nodeId/routes" -u "$apikey:" --data-binary @routes.json
echo ""