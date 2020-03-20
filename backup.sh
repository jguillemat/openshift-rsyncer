#!/bin/bash

# EXIT ERRORS
readonly E_NOPOD=253              # CANNOT GET POD NAME
readonly E_NOVOLUME=252           # POD_VOLUME not set
readonly E_NOERROR=0              # ALL IT's OK

# --------------------------------------
# FUNCTIONS
# --------------------------------------
is_empty() {
    local var="${1}"
    local empty=1

    if [[ -z "${var}" ]]; then
        empty=0
    fi
    return "${empty}"
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

# --------------------------------------
# MAIN METHOD
# --------------------------------------
main () {

    local -r src="/source"
    local -r dst="/backup"

    local -r pod_name="${POD_NAME}"
    local -r volume_data="${POD_VOLUME}"
    local -r pod_selector="${POD_SELECTOR}"
    local -r project="${PROJECT}"

    local -r bck_dir="${BCK_FOLDER}"

    echo "Checking Pod Volume to backup...."
    if [[ "${volume_data}" == "" ]]; then
        echo "ERROR: POD_VOLUME not specified. Exit."
        exit "${E_NOVOLUME}"
    fi

    echo "Checking Volume to store data...."
    if [[ "${bck_dir}" == "" ]]; then
        bck_dir="/data-replica"
    fi
           
    echo "Checking Pod Selector...."
    if [[ "${pod_selector}" == "" ]]; then
        echo "Setting default pod selector -> docker-registry=default" 
        pod_selector="docker-registry=default"
    fi        

 
    echo "Getting Pod Name"
    if [[ "${pod_name}" == "" ]]; then
        pod_name="$( get_pod_name ${selector} ${project} )"
        if [[ "${pod_name}" == "" ]]; then
            echo "ERROR: CANNOT GET POD_NAME. Exit."
            exit "${E_NOPOD}"
        fi  
    else
        echo "Specified POD_NAME=${pod_name} "
    fi

    dst_dir="${bck_dir}/"

    if [[ "${project}" == "" ]]; then
        echo "Start OC RSYNC from POD ${pod_name} into {dst_dir  ..."
        # oc rsync ${pod_name}:${src_dir} ${dst_dir} --progress 
    else 
        echo "Start OC RSYNC from POD ${pod_name} of project ${project} into {dst_dir..."
        # oc rsync ${pod_name}:${src_dir} ${dst_dir} --progress --namespace=${project}
    fi
    echo "End OC RSYNC."
}


main "$@"
exit "${E_NOERROR}"
