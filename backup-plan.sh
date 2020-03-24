#!/bin/bash
# 
# Descrition:           
#   Find in current namespace or in POD_PROJECT, a pod with "POD_SELECTOR" or "POD_NAME" 
#   to "$ oc rsync" data from "POD_VOLUME_PATH" to "REPLICA_VOLUME_PATH" inside this pod.
# 
# Parameters:
#   POD_PROJECT           (optional) namespace of source pod. Default: current namespace
#   POD_SELECTOR          (optional) node selector to find source pod.
#   POD_NAME              (optional) name of pod to connect for get data.
#   POD_VOLUME_PATH       (required) path inside pod to backup data.
#   REPLICA_VOLUME_PATH   (optional) path of backup PVC/PV to store data. Defaults: "//data-replica"
#   OC_RSYNC_OPTIONS      (optional) Parameters to pass to "oc rsync" . Defaults "--progress"
#   NATIVE_RSYNC_OPTIONS  (optional) Native parameters to pass to "rsync" . Defaults "-avpz --executability --acls --owner --group --times --specials --progress"

# EXIT ERRORS
readonly E_NOPODSELECTOR=254      # CANNOT GET POD SELECTOR
readonly E_NOPODNAME=253          # CANNOT GET POD NAME
readonly E_NOVOLUME=252           # POD_VOLUME not specified
readonly E_NOERROR=0              # ALL IT'S OK

# Configure rync into PATH

PATH=$PATH:

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

check_rsync_in_pod() {
    local p_name="${1}"
    local found=1

    $(oc exec $p_name rsync )
    if [ $? -eq 0 ]
    then
      echo "Successfully found rsync command"
      found=0
    else
      echo "Could not find rsync command" 
      found=1
    fi
    return "${found}"
}


log_msg() {
		echo "$(date +%Y%m%d%H%M) - $1"
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

    local oc_options="${OC_RSYNC_OPTIONS}"
    local rsync_options="${NATIVE_RSYNC_OPTIONS}"

    log_msg "Checking Pod Volume ${pod_volume_path} to backup...."
    if [[ "${pod_volume_path}" == "" ]]; then
        log_msg "ERROR: POD_VOLUME_PATH not specified. Exit."
        exit "${E_NOVOLUME}"
    fi

    log_msg "Checking Volume ${replica_volume_path} to store data...."
    if [[ "${replica_volume_path}" == "" ]]; then
        replica_volume_path="/data-replica"
    fi
           
    log_msg "Checking Pod Name ${pod_name}... "
    if [[ "${pod_name}" == "" ]]; then
    
        log_msg "Checking Pod Selector ${pod_selector} ...."
        if [[ "${pod_selector}" == "" ]]; then
            log_msg "ERROR: POD_SELECTOR or POD_NAME not specified. Exit."
            exit "${E_NOPODSELECTOR}"
        fi        
        
        pod_name="$( get_pod_name ${selector} ${project} )"
        log_msg "Found Pod Name ${pod_name} ...."
        if [[ "${pod_name}" == "" ]]; then
            log_msg "ERROR: CANNOT GET POD_NAME. Exit."
            exit "${E_NOPODNAME}"
        fi  
    else
        log_msg "Specified POD_NAME=${pod_name}"
    fi
    
    log_msg "Checking OC_RSYNC_OPTIONS ${oc_options}..."
    if [[ "${oc_options}" == "" ]]; then
        oc_options="--progress"
    fi        

    log_msg "Checking NATIVE_RSYNC_OPTIONS ${rsync_options}..."
#    if [[ "${rsync_options}" == "" ]]; then
#       rsync_options="-avpz --executability --acls --owner --group --times --specials"
#    fi        

#
    # Check final slash
    local source_dir="${pod_volume_path}"
    [[ "${pod_volume_path}" != */ ]] && source_dir="${pod_volume_path}/"
    [[ "${pod_volume_path}" == */ ]] && source_dir="${pod_volume_path}"
    
    # Check final slash
    local replica_dir=""
    [[ "${replica_volume_path}" != */ ]] && replica_dir="${replica_volume_path}/"
    [[ "${replica_volume_path}" == */ ]] && replica_dir="${replica_volume_path}"


    if [[ "${project}" == "" ]]; then
    
        if [[ "${rsync_options}" == "" ]]; then
            log_msg "Start OC RSYNC from DIR ${pod_volume_path} of POD ${pod_name} into ${replica_dir} with options ${oc_options} ..."
            oc rsync ${pod_name}:${source_dir} ${replica_dir} ${oc_options} 
        else
            log_msg "Start OC RSYNC from DIR ${pod_volume_path} of POD ${pod_name} into ${replica_dir} with options '${rsync_options}' ..."
            rsync ${rsync_options} ${pod_name}:${source_dir} ${replica_dir}
        fi 
    else 
        if [[ "${rsync_options}" == "" ]]; then
            log_msg "Start OC RSYNC from DIR ${source_dir} of POD ${pod_name} from NAMESPACE ${project} into ${replica_dir} with options '${oc_options}' ..."
            oc rsync ${pod_name}:${source_dir} ${replica_dir} ${oc_options} --namespace=${project}
        else
            log_msg "Start OC RSYNC from DIR ${source_dir} of POD ${pod_name} from NAMESPACE ${project} into ${replica_dir} with rsync options '${rsync_options}' ..."
            export RSYNC_RSH="oc rsh --namespace=${project}"
            rsync ${rsync_options} ${pod_name}:${source_dir} ${replica_dir}
        fi 
    fi

    sleep 60;
    log_msg "End of OC RSYNC"
}


PLAN_CONFIG="sync-plan.json"


while read pod_name pod_path ; do
	echo "hola"
	echo "$pod_name"
	echo "$pod_path"
done < <(jq -r '.SOURCE_PODS[]|"\(.POD_NAME) \(.POD_VOLUME_PATH)"' ${PLAN_CONFIG})



main "$@"




exit "${E_NOERROR}"
