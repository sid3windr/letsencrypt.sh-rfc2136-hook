#!/usr/bin/env bash

NSUPDATE="/usr/bin/nsupdate"
SERVER=10.1.1.53
PORT=53
TTL=300

DESTINATION=
OWNER=puppet
GROUP=puppet
MODE=0600

# Load letsencrypt.sh config
. $CONFIG

# If DOMAINS_TXT is set in the config, use it, if not, use default configuration.
[[ -z "${DOMAINS_TXT}" ]] && DOMAINS_TXT="${BASEDIR}/domains.txt"
  
function _log {
    echo >&2 "   + ${@}"
}

function _checkdns {
  local DOMAIN="${1}" TOKEN_VALUE="${2}"

  _log "Checking for dns propagation via Google's recursor..."

  # Allow at least a little time to propagate to slaves before asking Google
  sleep 5
                                                                                                                                                                                                                                             
  host -t txt _acme-challenge.${DOMAIN} 8.8.8.8 | grep ${TOKEN_VALUE} >/dev/null 2>&1                                                                                                                                                        
  if [ "$?" -eq 0 ]; then                                                                                                                                                                                                                    
    _log "Propagation success!"                                                                                                                                                                                                              
    return                                                                                                                                                                                                                                   
  else                                                                                                                                                                                                                                       
    _log "Waiting 30s..."                                                                                                                                                                                                                    
    sleep 30                                                                                                                                                                                                                                 
    _checkdns ${DOMAIN} ${TOKEN_VALUE}                                                                                                                                                                                                       
  fi                                                                                                                                                                                                                                         
}                                                                                                                                                                                                                                            
                                                                                                                                                                                                                                             
function deploy_challenge {                                                                                                                                                                                                                  
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

  _log "Adding ACME challenge record via RFC2136 update to ${SERVER}..."
  printf "server %s %s\nupdate add _acme-challenge.%s. %d in TXT \"%s\"\n\n" "${SERVER}" "${PORT}" "${DOMAIN}" "${TTL}" "${TOKEN_VALUE}" | $NSUPDATE
  _checkdns ${DOMAIN} ${TOKEN_VALUE}
}

function clean_challenge {
  local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

  # This hook is called after attempting to validate each domain,
  # whether or not validation was successful. Here you can delete
  # files or DNS records that are no longer needed.
  #
  # The parameters are the same as for deploy_challenge.

  _log "Removing ACME challenge record via RFC2136 update to ${SERVER}..."
  printf "server %s %s\nupdate delete _acme-challenge.%s. %d in TXT \"%s\"\n\n" "${SERVER}" "${PORT}" "${DOMAIN}" "${TTL}" "${TOKEN_VALUE}" | $NSUPDATE
}

function deploy_cert {
  local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" CHAINFILE="${4}"

  if [ "$DESTINATION" != "" ];
  then
    _log "Copying certificate files to destination repository"

    mkdir -p ${DESTINATION}/${DOMAIN}
    for FILE in ${KEYFILE} ${CERTFILE} ${CHAINFILE}
    do
      FILENAME=$(basename $FILE)
      cp ${FILE} ${DESTINATION}/${DOMAIN}

      if [ "$OWNER" != ""  ];
      then
        chown ${OWNER}:${GROUP} ${DESTINATION}/${DOMAIN}/${FILENAME}
      fi

      if [ "$MODE" != ""  ];
      then
        chmod ${MODE} ${DESTINATION}/${DOMAIN}/${FILENAME}
      fi
    done
  fi

  grep ^$HOST\$ ${DOMAINS_TXT} > /dev/null 2>&1
  if [ "$?" -ne 0 ]; then
    echo ${DOMAIN} >> ${DOMAINS_TXT}
  fi
}

function unchanged_cert {
  local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" CHAINFILE="${4}"

  # NOOP
}

HANDLER=$1; shift; $HANDLER $@
