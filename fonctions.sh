source ./config.cfg

####
## Contruction des headers avec -H :
####

curl_headers=()
for header in "${headers[@]}"; do
    curl_headers+=("-H" "$header")
done

####
#
# Fonction pour loger les différents actions et erreurs
# Non utilisé pour le moment
####

log() {
    local LEVEL=$1
    local MESSAGE=$2

    case "$LEVEL" in
        INFO)
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $MESSAGE" >&2
            ;;
        WARN)
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $MESSAGE" >&2
            ;;
        ERROR)
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $MESSAGE" >&2
            ;;
        DEBUG)
            if [ "$DEBUG" = "true" ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $MESSAGE" >&2
            fi
            ;;
        *)
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [UNKNOWN] $MESSAGE" >&2
            ;;
    esac
}




######
#
# Définition des fonctions 
#
######

# ========================================================================
# Nom de la fonction : generer_url_maj_dns
# Description     : Cette fonction construit l'url pour les appel API à nameshield pour mise à jour des enregistrement en fonction du FQDN et de la zone DNS associée.
# Paramètres      :
#   $1  - Zone DNS
# Valeur de retour : L'url à appeler est retournée
#
# Exemple d'utilisation :
#   result=$(generer_url_maj_dns('monsite.fr'))
#   echo "$result"
# ========================================================================
generer_url_maj_dns(){
    local URL_ZONES="$1"
    local ZONE="$2"
    echo "${URL_ZONES}/${ZONE}/records"
}


# ========================================================================
# Nom de la fonction : generer_url_validation_dns
# Description     : Cette fonction contruit l'url pour les appel API à nameshield pour valider les mises à jour des enregistrement en attente de validation
# Paramètres      :
#   $1  - Zone DNS
# Valeur de retour : L'url à appeler est retournée
#
# Exemple d'utilisation :
#   result=$(generer_url_validation_dns('monsite.fr'))
#   echo "$result"
# ========================================================================

generer_url_validation_dns(){
    local URL_ZONES="$1"
    local ZONE="$2"    
    echo "${URL_ZONES}/${ZONE}/validate"
}


# ========================================================================
# Nom de la fonction : set_json_data_api_nameshield
# Description     : Cette fonction récupère les variables d'environnement 
#                   générées par Certbot (par exemple : CERTBOT_DOMAINS, 
#                   CERTBOT_VALIDATION, etc.) et les convertit en un 
#                   objet JSON. Ce JSON peut être utilisé dans une requête 
#                   curl.
# Paramètres      : Aucun paramètre
# Valeur de retour : Objet JSON contenant les variables de Certbot pour envoyer à Nameshield.
#
# Exemple d'utilisation :
#   json_data=$(set_json_data_api_nameshield)
#   curl -X POST -d "$json_data" https://api.example.com
# ========================================================================

set_json_data_api_nameshield() {
    # Déclarer un tableau pour stocker les variables
    local certbot_vars=()
    local DOMAINE_A_VERIFIER=$1
    local CERTBOT_VALIDATION=$2        

     ###
     #
     # Récupération des variables depuis le config.cfg
     # MODEL_FQDN REMPLACEMENT_FQDN MODEL_FQDN_EXTERNE REMPLACEMENT_FQDN_EXTERNE
     ###


    # Ajouter les variables d'environnement à un tableau associatif pour conversion JSON
    if [[ -n "$DOMAINE_A_VERIFIER" ]]; then
        NOM_CHALLENGE=$(preparer_fqdn "${DOMAINE_A_VERIFIER}" "${MODEL_FQDN}" "${REMPLACEMENT_FQDN}" "${MODEL_FQDN_EXTERNE}" "${REMPLACEMENT_FQDN_EXTERNE}")
        certbot_vars+=("\"name\":\"$NOM_CHALLENGE\"")        
    fi
        if [[ -n "$CERTBOT_VALIDATION" ]]; then
        certbot_vars+=("\"data\":\"${CERTBOT_VALIDATION}\"")
    fi
    
    certbot_vars+=("\"type\":\"TXT\"")
    certbot_vars+=("\"ttl\":\"300\"")
    certbot_vars+=("\"comment\":\"ACME-DNS01-${DOMAINE_A_VERIFIER}\"")

    # Créer une chaîne JSON à partir du tableau
    json="{"
    json+=$(IFS=, ; echo "${certbot_vars[*]}")
    json+="}"

    # Retourner l'objet JSON
    echo $json
}  



# ========================================================================
# Nom de la fonction : nettoyer_fqdn
# Description     : Cette fonction nettoy les nom DNS pour les intégrer sans la partie liée à la zone
# Paramètres      : Nom de domaine concerné
# Valeur de retour : Le nom de domaine sans la partie qui correspond à la zone/souszone DNS
#
# Exemple d'utilisation :
#   nom=nettoyer_fqdn test.monsite.fr
# ========================================================================
nettoyer_fqdn() {
    local NDD=$1
    local LISTE_ZONES_P=$2    

    for chaine in $LISTE_ZONES_P; do
        # Suppression de la partie zone dans le NDD, nettoyage des points finaux et des espaces
        NDD=$(echo "$NDD" | sed -E "s/\b$chaine\b//g; s/\.$//g; s/^[[:space:]]+//; s/[[:space:]]+$//")
    done

    echo "$NDD"
}

preparer_fqdn(){  

    local FQDN=$1
    local PATTERN_FQDN=$2
    local REMPLACEMENT_FQDN=$3
    local PATTERN_FQDN_EXTERNE=$4
    local REMPLACEMENT_FQDN_EXTERNE=$5


    echo "$FQDN" | sed -E "
    s/^/_acme-challenge./;
    /$PATTERN_FQDN/ s/$PATTERN_FQDN/$REMPLACEMENT_FQDN/;
    /$PATTERN_FQDN/! s/$PATTERN_FQDN_EXTERNE/$REMPLACEMENT_FQDN_EXTERNE/;
"
}


# Fonction pour vérifier si une variable est définie
verifier_variable() {
    local var_name="$1"
    local var_value="$2"

    if [ -z "$var_value" ]; then
        log ERROR "La variable obligatoire '${var_name}' n'est pas définie."
        exit 3
    fi
}


# ========================================================================
# Nom de la fonction : get_liste_san
# Description     : Récupérer l'ensemble des SAN repris dans le fichier CSR
# Paramètres      : csr à parser
# Valeur de retour : La liste des SAN ex : site.exemple site2.exemple
# Cette fonction n'est plus utilisé dans le script mais peu servir pour des besoins annexes
#
# Exemple d'utilisation :
#   listeSAN=get_liste_san fichier.csr
# ========================================================================
get_liste_san(){

    local CSR=$1
    local LISTE_SAN=""
    
    $LISTE_SAN=$(openssl req -in $csr_file -noout -text | grep -oP '(?<=DNS:)[^,]*')

    echo $LISTE_SAN

}


# Vérifie l'état des zones DNS.
# Si la zone est en propagation il est inutile de travailler dessus pour le moment.
nb_zones_indisponibles() {

  local proxy="$1"
  local url_zones="$2"

  sleep 1

  # Utilisation correcte du tableau avec curl

  NB_ZONES_INDISPONIBLES=$(curl -L -s --proxy "$proxy" "${curl_headers[@]}" "$url_zones" | jq -r ".data.results | map(select(.status == \"DNS_PROPAGATION\")) | length")
  echo "$NB_ZONES_INDISPONIBLES"

}

