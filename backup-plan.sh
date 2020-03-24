#!/bin/bash
# 
# Descrition:           
#   Find in current namespace or in POD_PROJECT, a pod with "POD_SELECTOR" or "POD_NAME" 
#   to "$ oc rsync" data from "POD_VOLUME_PATH" to "REPLICA_VOLUME_PATH" inside this pod.
# 
# Parameters JSON FILE:
#
#    {
#	    "SOURCE_PODS": [ {
#		    "POD_PROJECT": "pvc-backuper",
#		    "POD_SELECTOR": "deploymentconfig=httpd",
#		    "POD_VOLUME_PATH": "/data",
#		    "REPLICA_VOLUME_PATH": "/data-replica/1"
#	    }, {
#		    "POD_PROJECT": "pvc-backuper",
#		    "POD_SELECTOR": "deploymentconfig=httpd1",
#		    "POD_VOLUME_PATH": "/data2",
#		    "REPLICA_VOLUME_PATH": "/data-replica/2"
#	    }, {
#		    "POD_PROJECT": "pvc-backuper",
#		    "POD_SELECTOR": "deploymentconfig=httpd2",
#		    "POD_VOLUME_PATH": "/data3",
#		    "REPLICA_VOLUME_PATH": "/data-replica/3"
#	    } 
#	    ], 
#	    "CONFIGURATION": {
#		    "OC_RSYNC_OPTIONS": "--progress",
#		    "NATIVE_RSYNC_OPTIONS": "-avz"
#	    }
#    } 


# EXIT ERRORS
readonly E_NOSYNCPLAN=255         # CANNOT GET SYNC PLAN
readonly E_NOPODSELECTOR=254      # CANNOT GET POD SELECTOR
readonly E_NOPODNAME=253          # CANNOT GET POD NAME
readonly E_NOVOLUME=252           # POD_VOLUME not specified
readonly E_NOERROR=0              # ALL IT'S OK

# Configure rsync into PATH
PATH=$PATH:/usr/bin/:.
export PATH

# --------------------------------------
# FUNCTIONS
# --------------------------------------


# --------------------------------------
#
is_empty() {
    local var="${1}"
    local empty=1

    if [[ -z "${var}" ]]; then
        empty=0
    fi
    return "${empty}"
}

# --------------------------------------
#
find_pod_name(){

    local p_project="${1}"
    local p_selector="${2}"
    local p_name=""

    if [[ "${p_project}" == "" ]]; then
        p_name=$(oc get po --selector=$p_selector --request-timeout=30s --no-headers -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | head -n1)
    else
        p_name=$(oc get po --namespace=$p_project --request-timeout=30s --selector=$p_selector --no-headers -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | head -n1)
    fi
    echo "${p_name}"	  
}

# --------------------------------------
#
check_rsync_in_pod() {
    local p_name="${1}"
    local found=1

    $(oc exec $p_name rsync  --request-timeout=30s )
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

# --------------------------------------
#
log_msg() {
		echo "$(date +%Y%m%d%H%M) - $1"
}


# --------------------------------------
# SYNCHRONIZE METHOD
# --------------------------------------

# param 1 : pod_project
# param 2 : pod_selector
# param 3 : p_volume_path
# param 4 : replica_volume_path

synchronize_data () {

    log_msg "Entering into synchronize_data ${*} ..."
    local p_project="$1"
    local p_selector="$2"
    local p_volume_path="$3"
    local replica_volume_path="$4"
    
    # log_msg "p_project=${p_project}"
    # log_msg "p_selector=${p_selector}"
    # log_msg "p_volume_path=${p_volume_path}"
    # log_msg "replica_volume_path=${replica_volume_path}"

           
    log_msg "Checking Pod Selector '${p_selector}' ..."
    if [[ "${p_selector}" == "" ]]; then
        log_msg "ERROR: POD_NAME not specified. Exit."
        exit "${E_NOPODSELECTOR}"
    fi        
        
    log_msg "Finding Pod with Pod Selector '${p_selector}' into project '${p_project}' ..."
    p_name="$( find_pod_name ${p_project} ${p_selector} )"
    if [[ "${p_name}" == "" ]]; then
        log_msg "ERROR: CANNOT GET POD_NAME. Exit."
        exit "${E_NOPODNAME}"
    fi  
    log_msg "Found Pod Name='${p_name}' ..."
    
    log_msg "Checking Pod Volume '${p_volume_path}' to get data ..."
    if [[ "${p_volume_path}" == "" ]]; then
        log_msg "ERROR: POD_VOLUME_PATH not specified. Exit."
        exit "${E_NOVOLUME}"
    fi

    log_msg "Checking Replica Volume '${replica_volume_path}' to store data ..."
    if [[ "${replica_volume_path}" == "" ]]; then
        replica_volume_path="/data-replica"
    fi

    # Check final slash
    local source_dir="${p_volume_path}"
    [[ "${p_volume_path}" != */ ]] && source_dir="${p_volume_path}/"
    [[ "${p_volume_path}" == */ ]] && source_dir="${p_volume_path}"
    
    # Check final slash
    local replica_dir=""
    [[ "${replica_volume_path}" != */ ]] && replica_dir="${replica_volume_path}/"
    [[ "${replica_volume_path}" == */ ]] && replica_dir="${replica_volume_path}"


    if [[ ! -d "$replica_dir" ]]; then
        mkdir -p $replica_dir; 
    fi
    
#    if [[ "${project}" == "" ]]; then
#    
#        if [[ "${NATIVE_RSYNC_OPTIONS}" == "" ]]; then
#            log_msg "Start OC RSYNC from DIR ${p_volume_path} of POD ${p_name} into ${replica_dir} with options ${OC_SYNC_OPTIONS} ..."
#            oc rsync ${p_name}:${source_dir} ${replica_dir} ${OC_SYNC_OPTIONS} 
#        else
#            log_msg "Start NATIVE RSYNC from DIR ${p_volume_path} of POD ${p_name} into ${replica_dir} with options '${NATIVE_RSYNC_OPTIONS}' ..."
#            rsync ${NATIVE_RSYNC_OPTIONS} ${p_name}:${source_dir} ${replica_dir}
#        fi 
#    else 
#        if [[ "${NATIVE_RSYNC_OPTIONS}" == "" ]]; then
#            log_msg "Start OC RSYNC from DIR ${source_dir} of POD ${p_name} from NAMESPACE ${project} into ${replica_dir} with options '${OC_SYNC_OPTIONS}' ..."
#            oc rsync ${p_name}:${source_dir} ${replica_dir} ${OC_SYNC_OPTIONS} --namespace=${project}
#        else
#            log_msg "Start NATIVE RSYNC from DIR ${source_dir} of POD ${p_name} from NAMESPACE ${project} into ${replica_dir} with rsync options '${NATIVE_RSYNC_OPTIONS}' ..."
#            export RSYNC_RSH="oc rsh --namespace=${project}"
#            rsync ${NATIVE_RSYNC_OPTIONS} ${p_name}:${source_dir} ${replica_dir}
#        fi 
#    fi

#    sleep 60;
    log_msg "End of OC RSYNC"
}


## ------------------------------------------ ##
## ------------------------------------------ ##
##                                            ## 
##    Main method                             ##
##                                            ##
## ------------------------------------------ ##
## ------------------------------------------ ##

# ------------------------------------------
# Check Plan file 
# ------------------------------------------
log_msg "Reading SYNC_PLAN_PATH parameter ..."
PLAN_DIR="${SYNC_PLAN_PATH}"
if [[ "${PLAN_DIR}" == "" ]]; then
    PLAN_DIR="./conf"
fi

# ------------------------------------------
# Check plan data 
# ------------------------------------------
log_msg "Getting PLAN_FILE parameter ..."
PLAN_FILE="${PLAN_DIR}/sync-plan.json"

if [[ ! -s "$PLAN_FILE" ]]; then
    log_msg "ERROR - Not sync plan data into '${PLAN_FILE}' "
    exit "${E_NOSYNCPLAN}" 
fi

# ------------------------------------------
# Get OC RSYNC OPTIONS
# ------------------------------------------
log_msg "Reading OC_RSYNC_OPTIONS parameter ..."
OC_SYNC_OPTIONS="${OC_RSYNC_OPTIONS}"

log_msg "Checking OC_RSYNC_OPTIONS ${OC_SYNC_OPTIONS}..."
if [[ "${OC_SYNC_OPTIONS}" == "" ]]; then
    OC_SYNC_OPTIONS="$( jq -r '.CONFIGURATION.OC_RSYNC_OPTIONS' ${PLAN_FILE} )"
    log_msg "Readed OC_RSYNC_OPTIONS ${OC_SYNC_OPTIONS}..."
    # OC_SYNC_OPTIONS="--progress"
fi        

# ------------------------------------------
# Get NATIVE RSYNC OPTIONS
# ------------------------------------------
log_msg "Reading NATIVE_RSYNC_OPTIONS parameter ..."
NATIVE_RSYNC_OPTIONS="${NATIVE_RSYNC_OPTIONS}"

log_msg "Checking NATIVE_RSYNC_OPTIONS ${NATIVE_RSYNC_OPTIONS}..."
if [[ "${NATIVE_RSYNC_OPTIONS}" == "" ]]; then
    NATIVE_RSYNC_OPTIONS="$( jq -r '.CONFIGURATION.NATIVE_RSYNC_OPTIONS' ${PLAN_FILE} )"
    log_msg "Readed NATIVE_RSYNC_OPTIONS ${NATIVE_RSYNC_OPTIONS}..."
    # NATIVE_RSYNC_OPTIONS="--progress"
fi        


# ------------------------------------------
# Process plan data 
# ------------------------------------------
log_msg "Starting processing sync plan file ..."
while read pod_project pod_selector p_volume_path replica_volume_path; 
do
    echo " ------------------------------------------------"
    echo " Reading JSON entry ..."
    echo " ------------------------------------------------"
	echo " pod_project=$pod_project"
	echo " pod_selector=$pod_selector"
	echo " p_volume_path=$p_volume_path"
	echo " replica_volume_path=$replica_volume_path"
	
	synchronize_data "${pod_project}" "${pod_selector}" "${p_volume_path}" "${replica_volume_path}"
	
done < <(jq -r '.SOURCE_PODS[]|"\(.POD_PROJECT) \(.POD_SELECTOR) \(.POD_VOLUME_PATH) \(.REPLICA_VOLUME_PATH)"' ${PLAN_FILE})


log_msg "Exit script with no error."
exit "${E_NOERROR}"
