#!/bin/bash

log() {
	echo "   $*" 1>&2
}

success() {
	echo " + $*" 1>&2
}

error() {
	echo "ERROR: $*" 1>&2
}

# exit inside a $() does not work, so we will roll out our own
scriptexitval=1
trap "exit \$scriptexitval" SIGKILL
abort() {
	scriptexitval=$1
	kill 0
}

cf_req() {
	local response=$(curl -s -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_KEY}" -H "Content-Type: application/json" $*)
	if [ $? -ne 0 ]; then
		error "HTTP request failed"
		abort 1
	fi

	local success=$(echo "$response" | jq -r ".success")
	if [ "$success" != true ]; then
		error "CloudFlare request failed"
		error "Response: $response"
		abort 1
	fi

	echo "$response"
}

get_domain() {
	local fqdn="$1"

	mawk -v fqdn="$fqdn" '
		BEGIN {
			best=""
		}

		{
			# Remove comments
			gsub(/\/\/.*/, "")

			# Remove spaces
			gsub(/[ \t]/, "")

			# If blank, skip
			if (length($0) == 0)
				next

			# Add leading dot
			tld="." $0

			# Check if this new TLD is longer and matches
			if (length(tld) > length(best) && substr(fqdn, length(fqdn) - length(tld) + 1) == tld) {
				best=tld
			}
		}

		END {
			# Remove TLD
			domain=substr(fqdn, 1, length(fqdn) - length(best))

			# Remove everything before the last dot - all subdomains, that is
			gsub(/^.*\./, "", domain)

			# Print appending TLD
			print domain best
		}
	' /usr/share/publicsuffix/effective_tld_names.dat
}

get_zone_id() {
	local fqdn="$1"
	local domain=$(get_domain "$fqdn")

	log "Requesting zone ID for $fqdn (domain: $domain)"

	local id=$(cf_req "https://api.cloudflare.com/client/v4/zones?name=${domain}" | jq -r ".result[0].id")

	if [ "$id" == null ]; then
		error "Unable to get zone ID for $fqdn"
		abort 1
	fi

	success "Zone ID: $id"

	echo "$id"
}

create_record() {
	local zone="$1"
	local fqdn="$2"
	local type="$3"
	local content="$4"
	local recordid

	log "Creating record $fqdn $type $content"

	recordid=$(cf_req -X POST "https://api.cloudflare.com/client/v4/zones/${zone}/dns_records" \
		--data "{\"type\":\"${type}\",\"name\":\"${fqdn}\",\"content\":\"${content}\"}" |
		jq -r ".result.id")

	if [ "$recordid" == null ]; then
		error "Error creating DNS record"
		abort 1
	fi

	echo "$recordid"
}

list_record_id() {
	local zone="$1"
	local fqdn="$2"

	cf_req "https://api.cloudflare.com/client/v4/zones/${zone}/dns_records?name=${fqdn}" |
	jq -r ".result[] | .id"
}

delete_records() {
	local zone="$1"
	local fqdn="$2"

	log "Deleting record(s) for $fqdn"

	list_record_id "$zone" "$fqdn" |
	while read recordid; do
		log " - Deleting $recordid"
		cf_req -X DELETE "https://api.cloudflare.com/client/v4/zones/${zone}/dns_records/${recordid}" >/dev/null
	done
}

deploy_challenge() {
	local fqdn="$2"
	local token="$4"
	local zoneid=$(get_zone_id "$fqdn")

	# Some cleanup before starting
	delete_records "$zoneid" "_acme-challenge.$fqdn"

	recordid=$(create_record "$zoneid" "_acme-challenge.$fqdn" TXT "$token")
	success "challenge created - CF ID: $recordid"
}

clean_challenge() {
	local fqdn="$2"
	local zoneid=$(get_zone_id "$fqdn")

	delete_records "$zoneid" "_acme-challenge.$fqdn"
}

case $1 in
	deploy_challenge)
		deploy_challenge $*
		;;

	clean_challenge)
		clean_challenge $*
		;;

	*)
		success "Ignoring call $1"
esac
