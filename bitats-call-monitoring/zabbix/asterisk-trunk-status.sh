#!/bin/bash
# Usage: asterisk-trunk-status.sh discover | status <username>

ACTION=$1
TRUNK=$2

REGISTRY=$(sudo /usr/sbin/asterisk -rx "sip show registry" 2>/dev/null | grep -v '^Host' | grep -v '^$' | grep -v 'SIP registrations')

case "$ACTION" in
  discover)
    echo '{"data":['
    FIRST=1
    while IFS= read -r line; do
      USERNAME=$(echo "$line" | awk '{print $3}')
      HOST=$(echo "$line" | awk '{print $1}')
      [ -z "$USERNAME" ] && continue
      [ $FIRST -eq 0 ] && echo ','
      printf '  {"{#TRUNK_USER}":"%s","{#TRUNK_HOST}":"%s"}' "$USERNAME" "$HOST"
      FIRST=0
    done <<< "$REGISTRY"
    echo ''
    echo ']}'
    ;;
  status)
    [ -z "$TRUNK" ] && exit 1
    LINE=$(echo "$REGISTRY" | awk -v t="$TRUNK" '$3 == t {print}')
    [ -z "$LINE" ] && echo "UNKNOWN" && exit 0
    STATE=$(echo "$LINE" | awk '{print $5}')
    FULL=$(echo "$LINE" | awk '{for(i=5;i<=NF;i++) printf $i" "; print ""}' | xargs)
    case "$FULL" in
      Registered*) echo "Registered" ;;
      Rejected*)   echo "Rejected" ;;
      "Request Sent") echo "Request Sent" ;;
      *) echo "$FULL" ;;
    esac
    ;;
  *)
    echo "Usage: $0 discover|status <username>"
    exit 1
    ;;
esac