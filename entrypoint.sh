#!/bin/bash

set -ex

# Constants
readonly DFT_LOG_FLR="/var/log/librebooking"
readonly DFT_LOG_LEVEL="none"
readonly DFT_LOG_SQL=false
readonly DFT_LB_ENV="production"
readonly DFT_LB_PATH=""

file_env() {
  local var="$1"
  local fileVar="${var}_FILE"
  local def="${2:-}"
  local varValue=$(env | grep -E "^${var}=" | sed -E -e "s/^${var}=//")
  local fileVarValue=$(env | grep -E "^${fileVar}=" | sed -E -e "s/^${fileVar}=//")
  if [ -n "${varValue}" ] && [ -n "${fileVarValue}" ]; then
      echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
      exit 1
  fi
  if [ -n "${varValue}" ]; then
      export "$var"="${varValue}"
  elif [ -n "${fileVarValue}" ]; then
      export "$var"="$(cat "${fileVarValue}")"
  elif [ -n "${def}" ]; then
      export "$var"="$def"
  fi
  unset "$fileVar"
}

# Exit if incompatible mount (images prior to V2)
if [ "$(mount | grep /var/www/html)" = "/var/www/html" ]; then
  echo "The volume must be mapped to container directory /config" >2
  exit 1
fi

# Initialize variables
file_env LB_INSTALL_PWD
file_env LB_DB_USER_PWD

LB_LOG_FOLDER=${LB_LOG_FOLDER:-${DFT_LOG_FLR}}
LB_LOG_LEVEL=${LB_LOG_LEVEL:-${DFT_LOG_LEVEL}}
LB_LOG_SQL=${LB_LOG_SQL:-${DFT_LOG_SQL}}
LB_ENV=${LB_ENV:-${DFT_LB_ENV}}
LB_PATH=${LB_PATH:-${DFT_LB_PATH}}

# If volume was used with images older than v2, then archive useless files
pushd /config
if [ -d Web ]; then
  mkdir archive
  chown www-data:www-data archive
  mv $(ls --ignore=archive) archive
  if [ -f archive/config/config.php ]; then
    cp archive/config/config.php config.php
    chown www-data:www-data config.php
  fi
fi
popd

# No configuration file inside directory /config
if ! [ -f /config/config.php ]; then
  echo "Initialize file config.php"
  if [ "${LB_ENV}" = "dev" ]; then
    cp /var/www/html/config/config.devel.php /config/config.php
  else
    cp /var/www/html/config/config.dist.php /config/config.php
  fi
  chown www-data:www-data /config/config.php
  sed \
    -i /config/config.php \
    -e "s:\(\['registration.captcha.enabled'\]\) = 'true':\1 = 'false':" \
    -e "s:\(\['database'\]\['user'\]\) = '.*':\1 = '${LB_DB_USER}':" \
    -e "s:\(\['database'\]\['password'\]\) = '.*':\1 = '${LB_DB_USER_PWD}':" \
    -e "s:\(\['database'\]\['name'\]\) = '.*':\1 = '${LB_DB_NAME}':"
fi

# Link the configuration file
if ! [ -f /var/www/html/config/config.php ]; then
  ln -s /config/config.php /var/www/html/config/config.php
fi

# Set secondary configuration settings
sed \
  -i /config/config.php \
  -e "s:\(\['install.password'\]\) = '.*':\1 = '${LB_INSTALL_PWD}':" \
  -e "s:\(\['default.timezone'\]\) = '.*':\1 = '${TZ}':" \
  -e "s:\(\['database'\]\['hostspec'\]\) = '.*':\1 = '${LB_DB_HOST}':" \
  -e "s:\(\['logging'\]\['folder'\]\) = '.*':\1 = '${LB_LOG_FOLDER}':" \
  -e "s:\(\['logging'\]\['level'\]\) = '.*':\1 = '${LB_LOG_LEVEL}':" \
  -e "s:\(\['logging'\]\['sql'\]\) = '.*':\1 = '${LB_LOG_SQL}':"

# Create the plugins configuration file inside the volume
for source in $(find /var/www/html/plugins -type f -name "*dist*"); do
  target=$(echo "${source}" | sed -e "s/.dist//")
  if ! [ -f "/config/$(basename ${target})" ]; then
    cp --no-clobber "${source}" "/config/$(basename ${target})"
    chown www-data:www-data "/config/$(basename ${target})"
  fi
  if ! [ -f ${target} ]; then
    ln -s "/config/$(basename ${target})" "${target}"
  fi
done

# Set timezone
if test -f /usr/share/zoneinfo/${TZ}; then
  ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime

  INI_FILE="/usr/local/etc/php/conf.d/librebooking.ini"
  echo "[date]" > ${INI_FILE}
  echo "date.timezone=\"${TZ}\"" >> ${INI_FILE}
fi

# Get log directory
log_flr=$(grep \
  -e "\['logging'\]\['folder'\]" \
  /var/www/html/config/config.php \
  | cut -d " " -f3 | cut -d "'" -f2)
log_flr=${log_flr:-${DFT_LOG_FLR}}

# Missing log directory
if ! test -d "${log_flr}"; then
  mkdir -p "${log_flr}"
  chown -R www-data:www-data "${log_flr}"
fi

# Missing log file
if ! test -f "${log_flr}/app.log"; then
  touch "${log_flr}/app.log"
  chown www-data:www-data "${log_flr}/app.log"
fi

# A URL path prefix was set
if ! test -z "${LB_PATH}"; then
  ## Set server document root 1 directory up
  sed \
    -i /etc/apache2/sites-enabled/000-default.conf \
    -e "s:/var/www/html:/var/www:"

  ## Rename the html directory as the URL prefix
  ln -s /var/www/html "/var/www/${LB_PATH}"
  chown www-data:www-data "/var/www/${LB_PATH}"

  ## Adapt the .htaccess file
  sed \
    -i /var/www/${LB_PATH}/.htaccess \
    -e "s:\(RewriteCond .*\)/Web/:\1\.\*/Web/:" \
    -e "s:\(RewriteRule .*\) /Web/:\1 /${LB_PATH}/Web/:"
fi

# Run the apache server
exec "$@"
