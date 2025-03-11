#!/bin/sh
set -e

#####
#
# Récupération des variables dans le fichier de configuration
#
#####
source ./fonctions.sh
source ./config.cfg

export http_proxy=$PROXY
export https_proxy=$PROXY


# Vérifier si $1 n'est pas nul
if [ -z "$1" ]; then
    log ERROR "Aucun paramètre passé."
    exit 1
fi

# Vérifier si le repertoire passé en param existe
if [ ! -d  "$1" ]; then
    log ERROR "Le repertoire ${$1} n'existe pas"
    exit 2
fi

REPERTOIRE_DE_TRAVAIL="$1"


CSR=${REPERTOIRE_DE_TRAVAIL}/${NOM_CSR}
# Vérifier si le fichier CSR existe
if [ ! -f "${CSR}" ]; then
    log ERROR "Aucune CSR trouvée"
    exit 3
fi


# Vérifications explicites des variables nécessaires
verifier_variable "MANUAL_AUTH_HOOK" "${MANUAL_AUTH_HOOK}"
verifier_variable "MANUAL_CLEANUP_HOOK" "${MANUAL_CLEANUP_HOOK}"
verifier_variable "PREFERRED_CHALLENGES" "${PREFERRED_CHALLENGES}"
verifier_variable "EAB_KIB" "${EAB_KIB}"
verifier_variable "EAB_HMAC_KEY" "${EAB_HMAC_KEY}"
verifier_variable "ACME_SERVER" "${ACME_SERVER}"
verifier_variable "ACME_EMAIL" "${ACME_EMAIL}"
verifier_variable "KEY_TYPE" "${KEY_TYPE}"
verifier_variable "REPERTOIRE_DE_TRAVAIL" "${REPERTOIRE_DE_TRAVAIL}"


##emplacement du certificat sous les différents format
EMPLACEMENT_CERTIFICAT="${REPERTOIRE_DE_TRAVAIL}/${NOM_CERTIFICAT}"
EMPLACEMENT_FULLCHAIN="${REPERTOIRE_DE_TRAVAIL}/${NOM_FULLCHAIN}"
EMPLACEMENT_CHAIN="${REPERTOIRE_DE_TRAVAIL}/${NOM_CHAIN}"
EMPLACEMENT_CERTIFICAT_DER="${REPERTOIRE_DE_TRAVAIL}/${NOM_CERTIFICAT_DER}"
EMPLACEMENT_CERTIFICAT_P7B="${REPERTOIRE_DE_TRAVAIL}/${NOM_CERTIFICAT_P7B}"

##Récupération de l'état des zones DNS
NB_ZONES_INDISPONIBLES=$(nb_zones_indisponibles "$PROXY" "$URL_ZONES" )

# Boucle while : Vérifier l'état des zones DNS si une zone est indisponible on attend 
# Vérifie si le vérrou let's encrypt est présent

START_TIME=$(date +%s)

while [ "$NB_ZONES_INDISPONIBLES" != 0 ] || [ -f ${CERTBOT_LOCK} ]; do
  CURRENT_TIME=$(date +%s)
  ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

  if [ "$ELAPSED_TIME" -ge "$TIMEOUT_VERIF" ]; then
    log ERROR "Timeout atteint après ${TIMEOUT_VERIF} secondes."
    exit 99
  fi

  log INFO "La génération ne peut pas être lancée pour le moment"
  log INFO "Nouvel tentative dans 10 secondes"
  
  sleep 10
  
  NB_ZONES_INDISPONIBLES=$(nb_zones_indisponibles "$PROXY" "$URL_ZONES" )
done


 certbot certonly --manual \
 --manual-auth-hook "${MANUAL_AUTH_HOOK}" \
 --manual-cleanup-hook "${MANUAL_CLEANUP_HOOK}" \
 --preferred-challenges ${PREFERRED_CHALLENGES} \
 --eab-kid ${EAB_KIB} \
 --eab-hmac-key ${EAB_HMAC_KEY} \
 --server ${ACME_SERVER} \
 --email ${ACME_EMAIL} \
 --key-type ${KEY_TYPE} \
 --csr "${CSR}" \
 --cert-path "${EMPLACEMENT_CERTIFICAT}" \
 --fullchain-path "${EMPLACEMENT_FULLCHAIN}" \
 --chain-path "${EMPLACEMENT_CHAIN}" \
 --work-dir "${REPERTOIRE_DE_TRAVAIL}" \
 --logs-dir "${REPERTOIRE_DE_TRAVAIL}" \
 --config-dir "${CERTBOT_REP_CLE}" \
 --non-interactive \
 --agree-tos \
 -q

sleep 10

# Vérification du code de sortie pour la conversion P7B
if [ $? -ne 0 ]; then
  log ERROR "Erreur avec la commande certbot"
fi

if [ ! -f ${EMPLACEMENT_CERTIFICAT} ]; then
  log ERROR "Aucun certificat reçu"
  exit 8
fi
##Convertion au format p7b
openssl crl2pkcs7 -nocrl -certfile ${EMPLACEMENT_FULLCHAIN} -out ${EMPLACEMENT_CERTIFICAT_P7B}

# Vérification du code de sortie pour la conversion P7B
if [ $? -ne 0 ]; then
  log WARN "La conversion au format P7B a échoué."
fi

##Convertir au format DER
openssl x509 -in ${EMPLACEMENT_CERTIFICAT} -outform DER -out ${EMPLACEMENT_CERTIFICAT_DER}
if [ $? -ne 0 ]; then
  log WARN "la conversion au format DER a échoué."
fi

exit 0