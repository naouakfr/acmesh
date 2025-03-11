#!/bin/sh
set -e

#####
#
# Récupération des variables dans le fichier de configuration
#
#####
source ./fonctions.sh
source ./config.cfg


####
# Domaine 
####
DOMAINE_A_VERIFIER=${CERTBOT_DOMAIN}


if [[ -z "${ZONEDNS}" ]]; then
    log ERROR "Aucune zone DNS définie dans le fichier config.cfg"
    exit 5
fi

##Génération des URL
URL_MAJ_ZONE_DNS=$(generer_url_maj_dns "${URL_ZONES}" "${ZONEDNS}")
URL_DNS_CONFIRMATION=$(generer_url_validation_dns "${URL_ZONES}" "${ZONEDNS}")

##Génération du JSON pour les appels curl
JSON=$(set_json_data_api_nameshield "${DOMAINE_A_VERIFIER}" "${CERTBOT_VALIDATION}" ) 

##Mise à jour de la zone DNS
DNSMAJ=$(curl -X POST ${URL_MAJ_ZONE_DNS} -s -L --proxy ${PROXY} "${curl_headers[@]}" -d $JSON )

if ! echo "$DNSMAJ" | jq empty 2>/dev/null || [ "$(echo "$DNSMAJ" | jq -r '.message')" != "Created" ]; then
    log ERROR "Erreur pour la mise à jour de la zone DNS"
    exit 6
fi


sleep 10

DNSVALIDATION=$(curl -X POST ${URL_DNS_CONFIRMATION} -s -L --proxy ${PROXY} "${curl_headers[@]}"  )

if ! echo "$DNSVALIDATION" | jq empty 2>/dev/null || [ "$(echo "$DNSVALIDATION" | jq -r '.message')" != "OK" ]; then
    log ERROR "Erreur pour la confirmation de la mise à jour DNS"
    exit 7
fi

sleep 10

START_TIME=$(date +%s)
NB_ZONES_INDISPONIBLES=$(nb_zones_indisponibles "$PROXY" "$URL_ZONES" )

# Boucle while : Vérifier l'état de la zone DNS. Si l'état est en propagation en cours en patiente

while [ "$NB_ZONES_INDISPONIBLES" != 0 ] ; do

    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

    if [ "$ELAPSED_TIME" -ge "$TIMEOUT_VERIF" ]; then
        log ERROR "Timeout atteint après ${TIMEOUT_VERIF} secondes."
        exit 99
    fi

    log INFO "La génération ne peut pas être lancée pour le moment"
    log INFO "Nouvel tentative dans 10 seconde"
    
    sleep 10
  
    NB_ZONES_INDISPONIBLES=$(nb_zones_indisponibles "$PROXY" "$URL_ZONES" )

done