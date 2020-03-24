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
readonly E_NOSYNCPLAN=255         # CANNOT GET SYNC PLAN
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

    local p_project="${1}"
    local p_selector="${2}"
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
# SYNCHRONIZE METHOD
# --------------------------------------
synchronize_data () {

    local -r src="/source"
    local -r dst="/backup"


    local p_project="${1}"
    local p_selector="${2}"
    local p_name="${3}"
    local p_volume_path="${4}"
    
    
    local replica_volume_path="${REPLICA_VOLUME_PATH}"

    local oc_options="${OC_RSYNC_OPTIONS}"
    local rsync_options="${NATIVE_RSYNC_OPTIONS}"

    log_msg "Checking Pod Volume ${p_volume_path} to backup...."
    if [[ "${p_volume_path}" == "" ]]; then
        log_msg "ERROR: POD_VOLUME_PATH not specified. Exit."
        exit "${E_NOVOLUME}"
    fi

    log_msg "Checking Volume ${replica_volume_path} to store data...."
    if [[ "${replica_volume_path}" == "" ]]; then
        replica_volume_path="/data-replica"
    fi
           
    log_msg "Checking Pod Name ${p_name}... "
    if [[ "${p_name}" == "" ]]; then
    
        log_msg "Checking Pod Selector ${p_selector} ...."
        if [[ "${p_selector}" == "" ]]; then
            log_msg "ERROR: POD_SELECTOR or POD_NAME not specified. Exit."
            exit "${E_NOPODSELECTOR}"
        fi        
        
        p_name="$( get_pod_name ${p_project} ${p_selector} )"
        log_msg "Found Pod Name ${p_name} ...."
        if [[ "${p_name}" == "" ]]; then
            log_msg "ERROR: CANNOT GET POD_NAME. Exit."
            exit "${E_NOPODNAME}"
        fi  
    else
        log_msg "Specified POD_NAME=${p_name}"
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
    local source_dir="${p_volume_path}"
    [[ "${p_volume_path}" != */ ]] && source_dir="${p_volume_path}/"
    [[ "${p_volume_path}" == */ ]] && source_dir="${p_volume_path}"
    
    # Check final slash
    local replica_dir=""
    [[ "${replica_volume_path}" != */ ]] && replica_dir="${replica_volume_path}/"
    [[ "${replica_volume_path}" == */ ]] && replica_dir="${replica_volume_path}"


    if [[ "${project}" == "" ]]; then
    
        if [[ "${rsync_options}" == "" ]]; then
            log_msg "Start OC RSYNC from DIR ${p_volume_path} of POD ${p_name} into ${replica_dir} with options ${oc_options} ..."
            oc rsync ${p_name}:${source_dir} ${replica_dir} ${oc_options} 
        else
            log_msg "Start OC RSYNC from DIR ${p_volume_path} of POD ${p_name} into ${replica_dir} with options '${rsync_options}' ..."
            rsync ${rsync_options} ${p_name}:${source_dir} ${replica_dir}
        fi 
    else 
        if [[ "${rsync_options}" == "" ]]; then
            log_msg "Start OC RSYNC from DIR ${source_dir} of POD ${p_name} from NAMESPACE ${project} into ${replica_dir} with options '${oc_options}' ..."
            oc rsync ${p_name}:${source_dir} ${replica_dir} ${oc_options} --namespace=${project}
        else
            log_msg "Start OC RSYNC from DIR ${source_dir} of POD ${p_name} from NAMESPACE ${project} into ${replica_dir} with rsync options '${rsync_options}' ..."
            export RSYNC_RSH="oc rsh --namespace=${project}"
            rsync ${rsync_options} ${p_name}:${source_dir} ${replica_dir}
        fi 
    fi

    sleep 60;
    log_msg "End of OC RSYNC"
}

# --------------------------------
# Main method
# 
# --------------------------------

# Check Plan file 
# ------------------------------------------

set PLAN_DIR="${SYNC_PLAN_PATH}"
if [[ "${PLAN_DIR}" == "" ]]; then
    PLAN_DIR = "/opt/app-root/conf"
fi
PLAN_FILE="${PLAN_DIR}/sync-plan.json"


# Check plan data 
# ------------------------------------------

if [[ -z $PLAN_FILE ]]; then
    log_msg "ERROR - Not sync plan data into ${PLAN_FILE} "
    exit "${E_NOSYNCPLAN}" 
fi;



# ------------------------------------------
# Process plan data 
# ------------------------------------------

while read pod_project pod_selector pod_name pod_path ; do
    echo "Reading entry ..."
	echo " pod_project=$pod_project"
	echo " pod_selector=$pod_selector"
	echo " pod_name=$pod_name"
	echo " pod_path=$pod_path"
	
	synchronize_data "$pod_project" "$pod_selector" "$pod_name" "$pod_path"
	
done < <(jq -r '.SOURCE_PODS[]|"\(.POD_PROJECT) \(.POD_SELECTOR) \(.POD_NAME) \(.POD_VOLUME_PATH)"' ${PLAN_FILE})

log_msg "Exit script with no error."
exit "${E_NOERROR}"
