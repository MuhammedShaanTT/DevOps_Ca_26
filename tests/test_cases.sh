#!/bin/bash
# ==============================================================================
# INT333 DevOps - Test Verification Suite (Sections 10 of Synopsis)
# ==============================================================================
KEY_FILE="$1"
WEB1_IP="$2"

if [ -z "$KEY_FILE" ] || [ -z "$WEB1_IP" ]; then
    echo "Usage: ./tests/test_cases.sh <key.pem> <web1-ip>"
    exit 1
fi

echo "--- Test 4: Testing URL Shortener HTTP Service ---"
RESPONSE=$(curl -s "http://$WEB1_IP/health")
echo "Health Response: $RESPONSE"
if [[ "$RESPONSE" == *"UP"* ]]; then
    echo "✅ TEST 4 PASSED: URL Shortener is healthy."
else
    echo "❌ TEST 4 FAILED: Service did not return UP."
fi

echo -e "\n--- Test 5: Simulating Service Outage & Self-Healing ---"
echo "Stopping urlshortener service manually on $WEB1_IP..."
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$WEB1_IP" "sudo systemctl stop urlshortener"

echo "Checking status (expecting inactive):"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$WEB1_IP" "systemctl is-active urlshortener || true"

echo "Running Puppet Agent to correct drift and self-heal..."
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$WEB1_IP" "sudo /opt/puppetlabs/bin/puppet agent -t || true"

echo "Checking status after Puppet run (expecting active):"
STATUS=$(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$WEB1_IP" "systemctl is-active urlshortener")
if [ "$STATUS" == "active" ]; then
    echo "✅ TEST 5 PASSED: Puppet self-healed the stopped service!"
else
    echo "❌ TEST 5 FAILED: Service is not active."
fi

echo -e "\n--- Test 6: Simulating Configuration Drift & Self-Healing ---"
echo "Corrupting /opt/urlshortener/app.py..."
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$WEB1_IP" "echo '# Corrupted content' | sudo tee /opt/urlshortener/app.py"

echo "Running Puppet Agent to restore desired file state..."
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$WEB1_IP" "sudo /opt/puppetlabs/bin/puppet agent -t || true"

GREP_CHECK=$(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$WEB1_IP" "grep -c 'Flask' /opt/urlshortener/app.py || true")
if [ "$GREP_CHECK" -gt 0 ]; then
    echo "✅ TEST 6 PASSED: Puppet restored the original file state."
else
    echo "❌ TEST 6 FAILED: File was not restored."
fi
