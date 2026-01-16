#!/bin/bash
# scripts/check-certs.sh
# Certificate Expiry Monitoring Script (SEC-004)
# Checks all certificates and warns if expiry is within threshold

set -e

CERT_DIR="${1:-./certs}"
WARN_DAYS="${2:-30}"
EXIT_CODE=0

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Certificate Expiry Monitor                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📁 Certificate Directory: $CERT_DIR"
echo "⚠️  Warning Threshold: $WARN_DAYS days"
echo ""

if [ ! -d "$CERT_DIR" ]; then
    echo "❌ ERROR: Certificate directory not found: $CERT_DIR"
    exit 1
fi

# Find all .crt files
CERTS=$(find "$CERT_DIR" -name "*.crt" -type f 2>/dev/null)

if [ -z "$CERTS" ]; then
    echo "❌ No certificates found in $CERT_DIR"
    exit 1
fi

echo "┌──────────────────────────────────────────────────────────────┐"
printf "│ %-25s │ %-12s │ %-15s │\n" "Certificate" "Expires" "Status"
echo "├──────────────────────────────────────────────────────────────┤"

while IFS= read -r cert; do
    cert_name=$(basename "$cert")
    
    # Get expiry date
    expiry_date=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
    
    if [ -z "$expiry_date" ]; then
        printf "│ %-25s │ %-12s │ %-15s │\n" "$cert_name" "INVALID" "❌ Error"
        EXIT_CODE=1
        continue
    fi
    
    # Convert to epoch for comparison
    if [[ "$OSTYPE" == "darwin"* ]]; then
        expiry_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
    else
        expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
    fi
    
    current_epoch=$(date +%s)
    warn_epoch=$((current_epoch + WARN_DAYS * 86400))
    
    # Format expiry for display
    if [[ "$OSTYPE" == "darwin"* ]]; then
        expiry_display=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" "+%Y-%m-%d" 2>/dev/null)
    else
        expiry_display=$(date -d "$expiry_date" "+%Y-%m-%d" 2>/dev/null)
    fi
    
    # Calculate days until expiry
    days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    # Determine status
    if [ "$expiry_epoch" -lt "$current_epoch" ]; then
        status="❌ EXPIRED"
        EXIT_CODE=2
    elif [ "$expiry_epoch" -lt "$warn_epoch" ]; then
        status="⚠️  ${days_left}d left"
        [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
    else
        status="✅ ${days_left}d left"
    fi
    
    printf "│ %-25s │ %-12s │ %-15s │\n" "$cert_name" "$expiry_display" "$status"
    
done <<< "$CERTS"

echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# Summary
case $EXIT_CODE in
    0)
        echo "✅ All certificates are valid and not expiring soon."
        ;;
    1)
        echo "⚠️  WARNING: Some certificates will expire within $WARN_DAYS days!"
        echo "   Run 'make clean && make certs' to regenerate."
        ;;
    2)
        echo "❌ CRITICAL: Some certificates have expired!"
        echo "   Run 'make clean && make certs' immediately!"
        ;;
esac

echo ""
echo "💡 Tip: Add this script to cron for automated monitoring:"
echo "   0 9 * * * cd /path/to/gateway && ./scripts/check-certs.sh >> /var/log/cert-check.log 2>&1"
echo ""

exit $EXIT_CODE
