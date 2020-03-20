#!/bin/bash

# EXIT ERRORS
readonly E_NOPODSELECTOR=254      # CANNOT GET POD SELECTOR
readonly E_NOPODNAME=253              # CANNOT GET POD NAME
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
    local p_selector="${1}"
    local p_project="${2}"
    local p_name=""
    if [[ "${p_project}" == "" ]]; then
        p_name=$(oc get po --selector=$p_selector --no-headers -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | head -n1)
    else
        p_name=$(oc get po --namespace=$p_project --selector=$p_selector --no-headers -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | head -n1)
    fi
    echo "${p_name}"	  
}

# --------------------------------------
# MAIN METHOD
# --------------------------------------
main () {

    local -r src="/source"
    local -r dst="/backup"

    local pod_name="${POD_NAME}"
    local -r pod_volume_path="${POD_VOLUME_PATH}"
    local -r project="${POD_PROJECT}"
    
    local -r pod_selector="${POD_SELECTOR}"
    local replica_volume_path="${REPLICA_VOLUME_PATH}"

    echo "Checking Pod Volume ${pod_volume_path} to backup...."
    if [[ "${pod_volume_path}" == "" ]]; then
        echo "ERROR: POD_VOLUME_PATH not specified. Exit."
        exit "${E_NOVOLUME}"
    fi

    echo "Checking Volume ${replica_volume_path} to store data...."
    if [[ "${replica_volume_path}" == "" ]]; then
        replica_volume_path="/data-replica"
    fi
           
    echo "Checking Pod Name ${pod_name}... "
    if [[ "${pod_name}" == "" ]]; then
    
        echo "Checking Pod Selector ${pod_selector} ...."
        if [[ "${pod_selector}" == "" ]]; then
            echo "ERROR: POD_SELECTOR or POD_NAME not specified. Exit."
            exit "${E_NOPODSELECTOR}"
        fi        
        
        pod_name="$( get_pod_name ${selector} ${project} )"
        echo "Found Pod Name ${pod_name} ...."
        if [[ "${pod_name}" == "" ]]; then
            echo "ERROR: CANNOT GET POD_NAME. Exit."
            exit "${E_NOPODNAME}"
        fi  
    else
        echo "Specified POD_NAME=${pod_name}"
    fi

    replica_dir="${replica_volume_path}/"

    if [[ "${project}" == "" ]]; then
        echo "Start OC RSYNC from POD ${pod_name} into ${replica_dir} ..."
        # oc rsync ${pod_name}:${pod_volume_path} ${replica_dir} --progress 
    else 
        echo "Start OC RSYNC from POD ${pod_name} of project ${project} into ${replica_dir}..."
        # oc rsync ${pod_name}:${pod_volume_path} ${replica_dir} --progress --namespace=${project}
    fi
    sleep 60;
    echo "End OC RSYNC."
}


main "$@"
exit "${E_NOERROR}"
