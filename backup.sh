#!/bin/bash

# EXIT ERRORS
readonly E_MNTFS=255              # ISSUE MOUNTING FILESYSTEM.
readonly E_EMPTYFS=254            # FILESYSTEM IS EMPTY
readonly E_NOPOD=253              # CANNOT GET POD NAME
readonly E_NOERROR=0              # ALL IT's OK


#FUNCTIONS

is_empty() {
  local var="${1}"
  local empty=1

  if [[ -z "${var}" ]]; then
    empty=0
  fi

  return "${empty}"
}

get_restrictive_id(){
  local fs="${1}"
  local id=""

  id="$( find ${fs} -maxdepth 1 -type f ! -perm -g+r ! -perm -o+r ! -path '*/\.*' -exec stat -c '%u:%g' {} \; | awk 'FNR == 1' )"

  echo "${id}"
}

get_id(){
  local fs="${1}"
  local id=""

  id="$( find ${fs} -maxdepth 1 -type f -exec stat -c '%u:%g' {} \; | awk 'FNR == 1' )"

  echo "${id}"
}

get_pod_name(){
	
  local selector="${1}"
  local project="${2}"

  local pod_name=""

  if [[ -z "${project}" ]]; then
	pod_name=$(oc get po --namespace=$project --selector=$selector --no-headers -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | head -n1)
  else
      	pod_name=$(oc get po --selector=$selector --no-headers -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | head -n1)
  fi

  echo "${pod_name}"	  
}

#FUNCTIONS
main () {

  local -r src="/source"
  local -r dst="/backup"

  local -r pod_name="${POD_NAME}"
  local -r volume_data="${POD_VOLUME}"
  local -r selector="${SELECTOR}"
  local -r project="${PROJECT}"


  local -r bck_dir="${BCK_FOLDER}"
  
  echo "Getting Pod Name"
  if [[ "${pod_name}" == "" ]]; then
    pod_name="$( get_pod_name ${selector} ${project} )"
    if [[ "${pod_name}" == "" ]]; then
       echo "ERROR: CANNOT GET POD_NAME. Exit."
	exit "${E_NOPOD}"
    fi  
  fi


  local src_dir="${src}/"
  if ! is_empty "${bck_dir}" && [[ -d "${src}/${bck_dir}" ]] ; then
    src_dir="${src}/${bck_dir}/"
  fi

  dst_dir="${dst}/"

  user_ugid="$( get_restrictive_id ${src_dir} )"
 
  if [[ "${user_ugid}" == "" ]]; then
    user_ugid="$( get_id ${src_dir} )"

    if [[ "${user_ugid}" == "" ]]; then
      echo "The file system/folder ${src_dir} is empty" 
      exit "${E_EMPTYFS}"
    fi

  fi

  user_uid=$(echo $user_ugid | cut -d':' -f1)
  user_gid=$(echo $user_ugid | cut -d':' -f2)


  if [[ "${project}" == "" ]]; then
	  echo "Start OC RSYNC ..."
	  oc rsync ${pod_name}:${src_dir} ${dst_dir} --progress 
  else 
	  echo "Start OC RSYNC from POD  into project ${project} ..."
	  oc rsync ${pod_name}:${src_dir} ${dst_dir} --progress --namespace=${project}
  fi
  echo "Ended OC RSYNC."

}


main "$@"

exit "${E_NOERROR}"
