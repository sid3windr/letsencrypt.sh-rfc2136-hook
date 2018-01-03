#!/bin/sh

# letsencrypt.sh dns-01 challenge RFC2136 hook.
# Copyright (c) 2016 Tom Laermans.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

# Load letsencrypt.sh config ($CONFIG is exported by letsencrypt.sh)
. $CONFIG

# All the below settings can be set in the letsencrypt.sh configuration file as well.
# They will not be overwritten by the statements below if they already exist in that configuration.

# NSUPDATE - Path to nsupdate binary
[ -z "${NSUPDATE}" ] && NSUPDATE="/usr/bin/nsupdate"

# NSUPDATEUSER - key user for nsupdate
[ -z "${NSUPDATEUSER}" ] && NSUPDATEUSER=""

# NSUPDATEKEY - key for nsupdate
[ -z "${NSUPDATEKEY}" ] && NSUPDATEKEY=""

# SERVER - Master DNS server IP
[ -z "${SERVER}" ] && SERVER="127.0.0.1"

# PORT - Master DNS port (likely to be 53)
[ -z "${PORT}" ] && PORT=53

# TTL - DNS Time-To-Live of ACME TXT record
[ -z "${TTL}" ] && TTL=300

# DESTINATION - Copy files to subdirectory of DESTINATION upon successful certificate request
[ -z "${DESTINATION}" ] && DESTINATION=

# CERT_OWNER - If DESTINATION and CERT_OWNER are set, chown files to CERT_OWNER after copy
[ -z "${CERT_OWNER}" ] && CERT_OWNER=

# CERT_GROUP - If DESTINATION, CERT_OWNER and CERT_GROUP are set, chown files to CERT_GROUP after copy
[ -z "${CERT_GROUP}" ] && CERT_GROUP=

# CERT_MODE - If DESTINATION and CERT_MODE are set, chmod files to CERT_MODE after copy
[ -z "${CERT_MODE}" ] && CERT_MODE=

# CERTDIR_OWNER - If DESTINATION and CERTDIR_OWNER are set, chown files to CERTDIR_OWNER after copy
[ -z "${CERTDIR_OWNER}" ] && CERTDIR_OWNER=

# CERTDIR_GROUP - If DESTINATION, CERTDIR_OWNER and CERTDIR_GROUP are set, chown files to CERTDIR_GROUP after copy
[ -z "${CERTDIR_GROUP}" ] && CERTDIR_GROUP=

# CERTDIR_MODE - If DESTINATION and CERT_MODE are set, chmod files to CERT_MODE after copy
[ -z "${CERTDIR_MODE}" ] && CERTDIR_MODE=

# ATTEMPTS - Wait $ATTEMPTS times $SLEEP seconds for propagation to succeed, then bail out.
[ -z "${ATTEMPTS}" ] && ATTEMPTS=10

# SLEEP - Amount of seconds to sleep before retrying propagation check.
[ -z "${SLEEP}" ] && SLEEP=30

# DOMAINS_TXT - Path to the domains.txt file containing all requested certificates.
[ -z "${DOMAINS_TXT}" ] && DOMAINS_TXT="${BASEDIR}/domains.txt"

_log() {
    echo >&2 "   + ${@}"
}

_checkdns() {
  local ATTEMPT="${1}" DOMAIN="${2}" TOKEN_VALUE="${3}"

  if [ $ATTEMPT -gt $ATTEMPTS ];
  then
    _log "Propagation check failed after ${ATTEMPTS} attempts. Bailing out!"
    exit 2
  fi

  _log "Checking for dns propagation via Google's recursor... (${ATTEMPT}/${ATTEMPTS})"

  host -t txt _acme-challenge.${DOMAIN} 8.8.8.8 | grep ${TOKEN_VALUE} >/dev/null 2>&1
  if [ "$?" -eq 0 ];
  then
    _log "Propagation success!"
    return
  else

    _log "Waiting ${SLEEP}s..."
    sleep ${SLEEP}
    _checkdns $((ATTEMPT+1)) ${DOMAIN} ${TOKEN_VALUE}
  fi
}

deploy_challenge() {
  local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

  # This hook is called once for every domain that needs to be
  # validated, including any alternative names you may have listed.
  #
  # Parameters:
  # - DOMAIN
  #   The domain name (CN or subject alternative name) being
  #   validated.
  # - TOKEN_FILENAME
  #   The name of the file containing the token to be served for HTTP
  #   validation. Should be served by your web server as
  #   /.well-known/acme-challenge/${TOKEN_FILENAME}.
  # - TOKEN_VALUE
  #   The token value that needs to be served for validation. For DNS
  #   validation, this is what you want to put in the _acme-challenge
  #   TXT record. For HTTP validation it is the value that is expected
  #   be found in the $TOKEN_FILENAME file.

  local QUERY="server %s %s\nupdate add _acme-challenge.%s. %d in TXT \"%s\""
  _log "Adding ACME challenge record via RFC2136 update to ${SERVER}..."
  if [ -n "$NSUPDATEUSER" -a -n "$NSUPDATEKEY" ]
      then
      QUERY="${QUERY}\nkey ${NSUPDATEUSER} ${NSUPDATEKEY}"
  fi
  printf "${QUERY}\n\n" "${SERVER}" "${PORT}" "${DOMAIN}" "${TTL}" "${TOKEN_VALUE}" | $NSUPDATE > /dev/null 2>&1
  if [ "$?" -ne 0 ];
  then
    _log "Failure reported by nsupdate. Bailing out!"
    exit 2
  fi

  # Allow at least a little time to propagate to slaves before asking Google
  sleep 5

  _checkdns 1 ${DOMAIN} ${TOKEN_VALUE}
}

clean_challenge() {
  local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

  # This hook is called after attempting to validate each domain,
  # whether or not validation was successful. Here you can delete
  # files or DNS records that are no longer needed.
  #
  # The parameters are the same as for deploy_challenge.

  local QUERY="server %s %s\nupdate delete _acme-challenge.%s. %d in TXT \"%s\""
  _log "Removing ACME challenge record via RFC2136 update to ${SERVER}..."
  if [ -n "${NSUPDATEUSER}" -a -n "${NSUPDATEKEY}" ]
      then
      QUERY="${QUERY}\nkey ${NSUPDATEUSER} ${NSUPDATEKEY}"
  fi
  printf "${QUERY}\n\n" "${SERVER}" "${PORT}" "${DOMAIN}" "${TTL}" "${TOKEN_VALUE}"| $NSUPDATE > /dev/null 2>&1
  if [ "$?" -ne 0 ];
  then
    _log "Failure reported by nsupdate. Bailing out!"
    exit 2
  fi
}

deploy_cert() {
  local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" CHAINFILE="${4}"

  # If destination is set, copy/chown/chmod certificate files
  if [ "$DESTINATION" != "" ];
  then
    _log "Copying certificate files to destination repository"

    mkdir -p ${DESTINATION}/${DOMAIN}
    if [ "$CERTDIR_MODE" != ""  ];
    then
      chmod ${CERTDIR_MODE} ${DESTINATION}/${DOMAIN}
    fi

    if [ "$CERTDIR_OWNER" != ""  ];
    then
      chown ${CERTDIR_OWNER}:${CERTDIR_GROUP} ${DESTINATION}/${DOMAIN}
    fi

    if [ "$CERTDIR_MODE" != ""  ];
    then
      chmod ${CERTDIR_MODE} ${DESTINATION}/${DOMAIN}
    fi

    for FILE in ${KEYFILE} ${CERTFILE} ${CHAINFILE}
    do
      FILENAME=$(basename $FILE)
      cp ${FILE} ${DESTINATION}/${DOMAIN}

      if [ "$CERT_OWNER" != ""  ];
      then
        chown ${CERT_OWNER}:${CERT_GROUP} ${DESTINATION}/${DOMAIN}/${FILENAME}
      fi

      if [ "$CERT_MODE" != ""  ];
      then
        chmod ${CERT_MODE} ${DESTINATION}/${DOMAIN}/${FILENAME}
      fi
    done
  fi

  # Add DOMAIN to domains.txt if not already there
  grep ^$HOST\$ ${DOMAINS_TXT} > /dev/null 2>&1
  if [ "$?" -ne 0 ];
  then
    echo ${DOMAIN} >> ${DOMAINS_TXT}
  fi
}

invalid_challenge() {
    local DOMAIN="${1}" RESPONSE="${2}"

    # This hook is called if the challenge response has failed, so domain
    # owners can be aware and act accordingly.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - RESPONSE
    #   The response that the verification server returned
    _log "Invalid challenge for ${DOMAIN}, response was ${RESPONSE}"
}

unchanged_cert() {
  # NOOP

  :
}

startup_hook() {
  # NOOP

  :
}

exit_hook() {
  # NOOP

  :
}

HANDLER=$1; shift; $HANDLER $@
