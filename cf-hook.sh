#!/bin/bash
# shellcheck disable=SC2155
# shellcheck disable=SC2162
# shellcheck disable=SC2181
# shellcheck disable=SC2173


log () {
	printf "   %s\n" "${*}" 1>&2
}

success () {
	printf " + %s\n" "${*}" 1>&2
}

error () {
	printf "ERROR: %s\n" "${*}" 1>&2
}

# exit inside a $() does not work, so we will roll out our own
scriptexitval=1
trap "exit \$scriptexitval" SIGKILL
abort () {
	scriptexitval=$1
	kill 0
}

cf_req () {
	local response
	
	localdir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
	if [[ -f "${localdir}/cftoken" ]]
    then
      source "${localdir}/cftoken"
  fi

	if [[ -n "${CF_TOKEN}" ]]
    then
      response=$( curl -s \
                  -H "Authorization: Bearer ${CF_TOKEN}" \
                  -H "Content-Type: application/json" \
                      "${@}"
                )     
	elif [[ -n "${CF_EMAIL}" ]] && [[ -n "${CF_KEY}" ]]
    then
      response=$( curl -s \
                  -H "X-Auth-Email: ${CF_EMAIL}" \
                  -H "X-Auth-Key: ${CF_KEY}" \
                  -H "Content-Type: application/json" \
                      "${@}"
                )        
	  else
      error "Missing CF keys"
      abort 1
	fi
	if [[ $? -ne 0 ]]
    then
      error "HTTP request failed"
      abort 1
	fi

	local success=$( printf "%s" "${response}" | jq -r ".success" )
	if [[ "${success}" != true ]]
    then
      error "CloudFlare request failed"
      error "Response: ${response}"
      abort 1
	fi

	printf "%s" "${response}"
}

get_domain () {
	local fqdn="${1}"
  if [[ $( printf "%s" "${fqdn}" | awk -F '.' '{ print NF }' ) -gt "2" ]]
    then
      printf "%s" "${fqdn}" | awk -F '.' '{ print $(NF-1)"."$NF }'
    else
      printf "%s" "${fqdn}"
  fi
}

get_zone_id () {
	local fqdn="${1}"
	local domain=$( get_domain "$fqdn" )

	log "Requesting zone ID for ${fqdn} (domain: ${domain})"

	local id=$(  cf_req "https://api.cloudflare.com/client/v4/zones?name=${domain}" \
               | jq -r ".result[0].id"
            )

	if [[ "${id}" == null ]]
    then
      error "Unable to get zone ID for ${fqdn}"
      abort 1
	fi

	success "Zone ID: ${id}"

	printf "%s" "${id}"
}

wait_for_publication () {
	local fqdn="${1}"
	local type="${2}"
	local content="${3}"

	local retries=12
	local delay=1000
	local delaySec

	while true
    do
      if ( dig +noall +answer @ns.cloudflare.com "${fqdn}" "${type}" \
          | awk '{ print $5 }' \
          | grep -qF "${content}"
        )
        then
          return
      fi

      if [[ ${retries} -eq 0 ]]
        then
          error "Record ${fqdn} did not get published in time"
          abort 1
        else
          delaySec=${delay:0:(-3)}.${delay:(-3)}
          log "Waiting ${delaySec} seconds..."
          sleep ${delaySec}

          retries=$((retries - 1))
          delay=$((delay * 15 / 10))
      fi
	done
}

create_record () {
	local zone="${1}"
	local fqdn="${2}"
	local type="${3}"
	local content="${4}"
	local recordid

	log "Creating record ${fqdn} ${type} ${content}"

	recordid=$( cf_req -X POST "https://api.cloudflare.com/client/v4/zones/${zone}/dns_records" \
		          --data "{\"type\":\"${type}\",\"name\":\"${fqdn}\",\"content\":\"${content}\"}" \
              | jq -r ".result.id"
            )

	if [[ "${recordid}" == null ]]
    then
      error "Error creating DNS record"
      abort 1
	fi

	printf "%s" "${recordid}"
}

list_record_id () {
	local zone="${1}"
	local fqdn="${2}"

	cf_req "https://api.cloudflare.com/client/v4/zones/${zone}/dns_records?name=${fqdn}" \
  |	jq -r ".result[] | .id"
}

delete_records () {
	local zone="${1}"
	local fqdn="${2}"

	log "Deleting record(s) for ${fqdn}"

	list_record_id "${zone}" "${fqdn}" \
  |	while read recordid
      do
        log " - Deleting ${recordid}"
        cf_req -X DELETE "https://api.cloudflare.com/client/v4/zones/${zone}/dns_records/${recordid}" >/dev/null
	done
}

deploy_challenge () {
	local fqdn="${2}"
	local token="${4}"
	local zoneid=$(get_zone_id "${fqdn}")

	recordid=$(create_record "${zoneid}" "_acme-challenge.${fqdn}" TXT "${token}")
	wait_for_publication "_acme-challenge.${fqdn}" TXT "\"${token}\""

	success "challenge created - CF ID: ${recordid}"
}

clean_challenge () {
	local fqdn="${2}"
	local zoneid=$(get_zone_id "${fqdn}")

	delete_records "${zoneid}" "_acme-challenge.${fqdn}"
}

case ${1} in
	deploy_challenge)
		deploy_challenge "${@}"
	;;
	clean_challenge)
		clean_challenge "${@}"
	;;
esac
