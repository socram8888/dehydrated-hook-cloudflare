#!/usr/bin/env bash

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

## Only scan for databases if the user doesn't specify a custom path
if [ -z "${DNS_SUFFIX_DATA}" ]; then
	for candidate in /usr/share/publicsuffix/effective_tld_names.dat /usr/local/share/public_suffix_list/public_suffix_list.dat; do
		if [ -f "${candidate}" ]; then
			DNS_SUFFIX_DATA="${candidate}"
			break
		fi
	done
fi

if [ ! -f "${DNS_SUFFIX_DATA}" ]; then
	error "No publicsuffix database found"
	abort 1
fi

if which drill &>/dev/null; then
	resolve_record() {
		drill "$1" "$2" @ns.cloudflare.com | sed -rn "s/^.*\.\t[0-9]+\tIN\t$2\t//p"
	}
elif which dig &>/dev/null; then
	resolve_record() {
		dig +short "$1" "$2" @ns.cloudflare.com
	}
else
	echo "No DNS lookup tool installed. Please install either dig or drill"
	abort 1
fi

cf_req() {
	local response
	if [ ! -z "${CF_TOKEN}" ]; then
		response=$(curl -s -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json" $*)
	elif [ ! -z "${CF_EMAIL}" ] && [ ! -z "${CF_KEY}" ]; then
		response=$(curl -s -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_KEY}" -H "Content-Type: application/json" $*)
	else
		error "Missing CF keys"
		abort 1
	fi
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

	awk -v fqdn="$fqdn" '
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
	' "${DNS_SUFFIX_DATA}"
}

list_record_id() {
	local zone="$1"
	local fqdn="$2"

	cf_req "https://api.cloudflare.com/client/v4/zones/${zone}/dns_records?name=${fqdn}" |
	jq -r ".result[] | .id"
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

wait_for_publication() {
	local fqdn="$1"
	local type="$2"
	local content="$3"

	local retries=12
	local delay=1000
	local delaySec

	while true; do
		if resolve_record "$fqdn" "$type" | grep -qF "$content"; then
			return
		fi

		if [ $retries -eq 0 ]; then
			error "Record $fqdn did not get published in time"
			abort 1
		else
			delaySec=${delay:0:(-3)}.${delay:(-3)}
			log "Waiting $delaySec seconds..."
			sleep $delaySec

			retries=$(($retries - 1))
			delay=$(($delay * 15 / 10))
		fi
	done
}

create_record() {
	local zone="$1"
	local fqdn="$2"
	local type="$3"
	local content="$4"
	local recordid

	log "Checking for already existing record $fqdn"
	current_ids=$(list_record_id "$zone" "$fqdn")
	if [ -n "${current_ids}" ]; then
		log "Existing record found (from previous failed attempt?) Deleting."
		echo "${current_ids}" | while read recordid; do
			log " - Deleting $recordid"
			cf_req -X DELETE "https://api.cloudflare.com/client/v4/zones/${zone}/dns_records/${recordid}" >/dev/null
		done
	else
		log "No existing record"
	fi


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

	recordid=$(create_record "$zoneid" "_acme-challenge.$fqdn" TXT "$token")
	wait_for_publication "_acme-challenge.$fqdn" TXT "\"$token\""

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
esac

## Keep the file consistent with upstream as they use tabs for indent, not
## spaces.
##
# Local Variables:
# indent-tabs-mode: t
# End:

## Similar for Vim users.  Make sure that the 'modeline' option is
## enabled in Vim before assuming the below setting is working.  You
## can do `:set modeline?` to verify.
##
# vim: set noexpandtab tabstop=4 shiftwidth=4 :
