#!/bin/bash
# 
# Descrition:           
#   Script para la sincronización de un conjunto de volumenes de glusterfs (pv/pvc) hacia un servidor remoto con
#   acceso ssh/rsync.
#   El servidore remote (SSH_SERVER) debe poder montar el servicio NFS en local.
#
#   Configuracion basado en un fichero de configuración:
#
#    {
#	    "SOURCE_VOLUMES": [ {
#		    "NAMESPACE": "pvc-backuper",
#		    "PVC": "data-pvc",
#		    "PV": "pvc-0e48b67d-6a98-11ea-a00e-001a4a461c22",
#		    "GLUSTER_MOUNT_DATA": "vol_4619cd02f4cf514517c6043e33008f3d",
#		    "PVC_REPLICA": "replica-pvc"
#	    }, {
#		    "NAMESPACE": "pvc-backuper",
#		    "PVC": "data-pvc",
#		    "PV": "pvc-0e48b67d-6a98-11ea-a00e-001a4a461c22",
#		    "GLUSTER_MOUNT_DATA": "vol_4619cd02f4cf514517c6043e33008f3d",
#		    "PVC_REPLICA": "replica-pvc"
#	    }, {
#		    "NAMESPACE": "pvc-backuper",
#		    "PVC": "data-pvc",
#		    "PV": "pvc-0e48b67d-6a98-11ea-a00e-001a4a461c22",
#		    "GLUSTER_MOUNT_DATA": "vol_4619cd02f4cf514517c6043e33008f3d",
#		    "PVC_REPLICA": "replica-pvc"
#	    }
#	    ], 
#	    "CONFIGURATION": {
#		    "SSH_SERVER": "ocp-nexica-bastion.uoc.es",
#           "REMOTE_NFS_ENDPOINT": "vdm-oscont.uoc.es:/PRO_openshift_repo/",
#		    "REMOTE_REPLICA_DIR": "/mnt/nfs/",
#		    "LOCAL_DATA_DIR": "/tmp/nfs/",
#		    "RSYNC_OPTIONS": "-avz"
#	    }
#    } 


# EXIT ERRORS
readonly E_NOSYNCPLAN=255         # CANNOT GET SYNC PLAN FILE
readonly E_SYNCPLAN_EMPTY=254     # CANNOT GET SYNC PLAN DATA
readonly E_NONAMESPACE=253         # CANNOT GET NAMESPACE
readonly E_CANNOT_MOUNT_GLUSTER=252 # CANNOT MOUNT GLUSTERVOL INTO LOCAL DIR
readonly E_CANNOT_MOUNT_REMOTE=251   # CANNOT MOUNT REMOTE NFS ENDPOINT
readonly E_NOSSH_CONNECTION=250     # Cannot establish a SSH connection
readonly E_NOERROR=0              # ALL IT'S OK

# Configure rsync into PATH
PATH=$PATH:/usr/bin/:.
export PATH

# --------------------------------------
# GLOBAL VARIABLES
# --------------------------------------


# --------------------------------------
# FUNCTIONS
# --------------------------------------

# --------------------------------------
#
function log_msg() {
    echo "$(date +%Y%m%d%H%M) - $@"
    echo -e "$(date +%Y%m%d%H%M) - $@" 1>&2 >> $LOG_FILE
}

function error_msg() {
    echo "$(date +%Y%m%d%H%M) - $@" 1>&2;
    echo -e "$(date +%Y%m%d%H%M) - $@" >> $LOG_FILE
}

# --------------------------------------
#
function check_ssh_session() {

    if execute_remote "hostname > /dev/null 2>&1"
    then
        log_msg "ssh exist ok"
        return "0";
    else
        error_msg "ERROR - Some error succeded in ssh process"
        return "$E_NOSSH_CONNECTION"
    fi
     return "0";
}

function execute_remote() {
    # log_msg "Executing SSH: '$@' "
    ssh ${p_ssh_server} "$p_ssh_options" "$@"
}
# --------------------------------------
# SYNCHRONIZE METHOD
# --------------------------------------

function synchronize_data() {

    log_msg "Entering into synchronize_data ${*} ..."
    local p_namespace="$1"
    local p_pvc="$2"
    local p_mount_data="$3"
    local p_pvc_replica="$4"
 
    log_msg "Checking Namespace '${p_namespace}' ..."
    if [[ "${p_namespace}" == "" ]]; then
        error_msg "ERROR: NAMESPACE not specified. Exit."
        return "${E_NONAMESPACE}"
    fi        
        
    log_msg " ------------------------------------------------"
    log_msg " Mount GlusterVol locally via Gluster"
    log_msg " ------------------------------------------------"

    # Check final slash
    local source_dir=""
    [[ "${p_local_data_dir}" != */ ]] && p_local_data_dir="${p_local_data_dir}/"
    [[ "${p_pvc}" != */ ]] && source_dir="${p_local_data_dir}${p_namespace}/${p_pvc}/"
    [[ "${p_pvc}" == */ ]] && source_dir="${p_local_data_dir}${p_namespace}/${p_pvc}"

    log_msg "Check local directory ${source_dir}."
    if [ -d "$source_dir" ]; then
        log_msg "Local directory already ${source_dir} exist."
    else 
        log_msg "Creating local directory ${source_dir}."
        mkdir -p "${source_dir}"
    fi

    mount_dir=${p_mount_data%/}
    log_msg "Check local mount point into ${mount_dir}."
    if mount | grep ${mount_dir} > /dev/null; then
         log_msg "GlusterVol already mounted locally"
    else 
        log_msg "Mounting GlusterVol '${p_mount_data}' into '${source_dir}' "
        if mount -t glusterfs ${p_mount_data} ${source_dir} -o ro  > /dev/null; then
            log_msg "GlusterVol mounted locally"
        else 
            error_msg "ERROR Mounting GlusterVol '${p_mount_data}' into '${source_dir}' "
            return "${E_CANNOT_MOUNT_GLUSTER}"
        fi
    fi

    log_msg " ------------------------------------------------"
    log_msg " Mount NFS Endpoint in remote server"
    log_msg " ------------------------------------------------"

    remote_mount_dir=${p_remote_replica_dir%/}
    log_msg "REMOTE: Check remote mount point into ${remote_mount_dir}."
    if execute_remote "mount | grep $remote_mount_dir > /dev/null 2>&1"
    then
        log_msg "REMOTE: NFS Endpoint already mounted in ${p_remote_replica_dir}."
    else
        log_msg "REMOTE: NFS Endpoint isn't mounted. Creating."
        log_msg "REMOTE: Check remote mount directory exist in ${p_remote_replica_dir}."
        if execute_remote "test -d $p_remote_replica_dir > /dev/null 2>&1"
        then
            log_msg "REMOTE: Remote mount directory already exist."
        else
            log_msg "REMOTE: Creating remote mount directory '${p_remote_replica_dir}'."
            execute_remote "mkdir -p ${p_remote_replica_dir}"
        fi    
        log_msg "REMOTE: Mounting NFS in '${p_remote_replica_dir}' into remote server"
        if execute_remote "mount -t nfs ${p_remote_nfs_endpoint} ${p_remote_replica_dir}"
        then
            log_msg "REMOTE: Remote mount directory mounted successfully."
        else
            error_msg "REMOTE: ERROR Mounting NFS '${p_remote_nfs_endpoint}' into '${sourp_remote_nfs_endpointce_dir}' "
            return "${REMOTE}"
        fi 
    fi

    log_msg "# -----------------------------------------------------------------"
    log_msg "# Create (if no exist) replica directory into remote server"
    # -----------------------------------------------------------------""
    local replica_dir=""
    [[ "${p_remote_replica_dir}" != */ ]] && p_remote_replica_dir="${p_remote_replica_dir}/"
    namespace_dir="${p_remote_replica_dir}${p_namespace}/"

    if execute_remote "test -d $namespace_dir > /dev/null 2>&1"
    then
        log_msg "REMOTE: Remote namespace directory already exist."
    else
        log_msg "REMOTE: Creating remote mount directory '${p_remote_replica_dir}'."
        log_msg "Creating remote namespace directory '${namespace_dir}'."
        execute_remote "mkdir -p ${namespace_dir}"
        execute_remote "chown nfsnobody:nfsnobody ${namespace_dir}"
    fi    

    [[ "${p_pvc_replica}" != */ ]] && replica_dir="${p_remote_replica_dir}${p_namespace}/${p_pvc_replica}/"
    [[ "${p_pvc_replica}" == */ ]] && replica_dir="${p_remote_replica_dir}${p_namespace}/${p_pvc_replica}"
    if execute_remote "test -d $replica_dir > /dev/null 2>&1"
    then
        log_msg "REMOTE: Remote pvc directory already exist."
    else
        log_msg "Creating remote pvc replica directory '${replica_dir}'."
        execute_remote "mkdir -p ${replica_dir}"
        execute_remote "chown nfsnobody:nfsnobody ${replica_dir}"
    fi    
   
    log_msg " ------------------------------------------------"
    log_msg " Start rsync data"
    log_msg " ------------------------------------------------"

    log_msg "Native RSYNC starts for PV '${p_pvc}' from DIR '${source_dir}' from NAMESPACE ${p_namespace} into ${replica_dir} with rsync options '${p_rsync_options}' ..."
    rsync ${p_rsync_options} ${source_dir} ${p_ssh_server}:/${replica_dir}
    if [ $? == 0 ]; then
        log_msg "Native RSYNC finished successfully"
    else
        error_msg "ERROR - Some error succeded in rsync process"
    fi
 
    # ---------------------------------------------
    # Umount Gluster Volume localy
    # ---------------------------------------------
    # log_msg "Unmounting GlusterVol from '${source_dir}' "
    # umount ${source_dir} --force

    # ---------------------------------------------
    # Umount Remote NFS Replica dir
    # ---------------------------------------------
    # log_msg "Umounting NFS from '${p_remote_replica_dir}' into remote server"
    # execute_remote "umount ${p_remote_replica_dir} --force"
    
    log_msg "End of Volume synchronization"
    # return "$E_NOERROR";
    return 0;
}

## ------------------------------------------ ##
## ------------------------------------------ ##
##                                            ## 
##    Main method                             ##
##                                            ##
## ------------------------------------------ ##
## ------------------------------------------ ##


# ------------------------------------------
# Check log file 
# ------------------------------------------
LOG_DIR="${LOGS_PATH}"
if [[ "${LOG_DIR}" == "" ]]; then
    LOG_DIR="./logs"
fi
LOG_FILE="${LOG_DIR}/syncrhonization_execution.log"
touch $LOG_FILE

# ------------------------------------------
# Check sync plan file 
# ------------------------------------------
log_msg "Reading SYNC_PLAN_PATH parameter ..."
PLAN_DIR="${SYNC_PLAN_PATH}"
if [[ "${PLAN_DIR}" == "" ]]; then
    PLAN_DIR="./conf"
fi

# ------------------------------------------
# Check sync plan data 
# ------------------------------------------
log_msg "Getting PLAN_FILE parameter ..."
PLAN_FILE="${PLAN_DIR}/local-sync-plan.json"

if [[ ! -e "$PLAN_FILE" ]]; then
    error_msg "ERROR - Sync plan file doesn't exist '${PLAN_FILE}' "
    exit "${E_NOSYNCPLAN}" 
fi
if [[ ! -s "$PLAN_FILE" ]]; then
    error_msg "ERROR - Not sync plan data into '${PLAN_FILE}' "
    exit "${E_SYNCPLAN_EMPTY}" 
fi
log_msg "Getted PLAN_FILE = '${PLAN_FILE}'."

# ------------------------------------------
# Get SSH_SERVER option
# ------------------------------------------
log_msg "Reading SSH_SERVER parameter ..."
p_ssh_server="${SSH_SERVER}"
log_msg "Checking SSH_SERVER ${p_ssh_server}..."
if [[ "${p_ssh_server}" == "" ]]; then
    p_ssh_server="$( jq -r '.CONFIGURATION.SSH_SERVER' ${PLAN_FILE} )"
    log_msg "Readed SSH_SERVER '${p_ssh_server}'"
fi

# ------------------------------------------
# Get SSH_OPTIONS option
# ------------------------------------------
p_ssh_options="${SSH_OPTIONS}"
log_msg "Checking SSH_OPTIONS ${p_ssh_options}..."
if [[ "${p_ssh_options}" == "" ]]; then
    p_ssh_options="$( jq -r '.CONFIGURATION.SSH_OPTIONS' ${PLAN_FILE} )"
    log_msg "Readed SSH_OPTIONS '${p_ssh_options}'"
fi

# ------------------------------------------
# Check SSH Connection
# ------------------------------------------
if check_ssh_session
then 
    log_msg "SSH connection available"
else
    error_msg "ERROR - SSH connection no available"
    exit "${E_NOSSH_CONNECTION}" 
fi

# ------------------------------------------
# Get REMOTE_NFS_ENDPOINT option
# ------------------------------------------
log_msg "Reading REMOTE_NFS_ENDPOINT parameter ..."
p_remote_nfs_endpoint="${REMOTE_NFS_ENDPOINT}"
log_msg "Checking REMOTE_NFS_ENDPOINT ${p_remote_nfs_endpoint}..."
if [[ "${p_remote_nfs_endpoint}" == "" ]]; then
    p_remote_nfs_endpoint="$( jq -r '.CONFIGURATION.REMOTE_NFS_ENDPOINT' ${PLAN_FILE} )"
    error_msg "Readed REMOTE_NFS_ENDPOINT '${p_remote_nfs_endpoint}'"
fi

# ------------------------------------------
# Get REMOTE_REPLICA_DIR option
# ------------------------------------------
log_msg "Reading REMOTE_REPLICA_DIR parameter ..."
p_remote_replica_dir="${REMOTE_REPLICA_DIR}"
log_msg "Checking REMOTE_REPLICA_DIR ${p_remote_replica_dir}..."
if [[ "${p_remote_replica_dir}" == "" ]]; then
    p_remote_replica_dir="$( jq -r '.CONFIGURATION.REMOTE_REPLICA_DIR' ${PLAN_FILE} )"
    log_msg "Readed REMOTE_REPLICA_DIR '${p_remote_replica_dir}'"
fi

# ------------------------------------------
# Get LOCAL_DATA_DIR option
# ------------------------------------------
log_msg "Reading LOCAL_DATA_DIR parameter ..."
p_local_data_dir="${LOCAL_DATA_DIR}"
log_msg "Checking LOCAL_DATA_DIR ${p_local_data_dir}..."
if [[ "${p_local_data_dir}" == "" ]]; then
    p_local_data_dir="$( jq -r '.CONFIGURATION.LOCAL_DATA_DIR' ${PLAN_FILE} )"
    log_msg "Readed LOCAL_DATA_DIR '${p_local_data_dir}'"
fi
 
# ------------------------------------------
# Get RSYNC option
# ------------------------------------------
log_msg "Reading RSYNC_OPTIONS parameter ..."
p_rsync_options="${RSYNC_OPTIONS}"
log_msg "Checking RSYNC_OPTIONS ${p_rsync_options}..."
if [[ "${p_rsync_options}" == "" ]]; then
    p_rsync_options="$( jq -r '.CONFIGURATION.RSYNC_OPTIONS' ${PLAN_FILE} )"
    log_msg "Readed RSYNC_OPTIONS '${p_rsync_options}'"
fi        

# ------------------------------------------
# Process plan data 
# ------------------------------------------
log_msg "Starting processing sync plan file ..."

list=$(cat "$PLAN_FILE" | jq -r '.SOURCE_VOLUMES[]|"\(.NAMESPACE) \(.PVC) \(.GLUSTER_MOUNT_DATA) \(.PVC_REPLICA)"')

ORIG_IFS=$IFS        # Save the original IFS
LINE_IFS=$'\n'$'\r'  # For splitting input into lines
FIELD_IFS=$'\n';     # For splitting lines into fields
IFS=$LINE_IFS
for line in $list; do
    echo " Processed LINE=${line}"
    IFS=$FIELD_IFS

    linea=($line)
    unset IFS;
    echo "${line}" | while read -r a b c d
    do
        p_namespace=$a
        p_pvc=$b
        p_mount_data=$c
        p_pvc_replica=$d

        log_msg " ------------------------------------------------"
        log_msg " read_parameters ..."
        log_msg " ------------------------------------------------"
        log_msg "p_namespace=$p_namespace"
        log_msg "p_pvc=$p_pvc"
        log_msg "p_mount_data=$p_mount_data"
        log_msg "p_pvc_replica=$p_pvc_replica"

        # ------------------------------------------
        # Process plan entry
        # ------------------------------------------.
        if [ -n "$p_namespace" ] && [ -n "$p_pvc" ] && [ -n "$p_mount_data" ] && [ -n "$p_pvc_replica" ]; then
            log_msg "Calling synchronize_data method"
            synchronize_data ${p_namespace} ${p_pvc} ${p_mount_data} ${p_pvc_replica}
            if [ $? == 0 ]; then
                log_msg "synchronize_data exists ok"
            else
                error_msg "ERROR - Some error succeded in synchronize_data"
            fi
        else
            error_msg "ERROR - Some required parameter not speciefied"
        fi
        
    done
    IFS=$LINE_IFS
done
IFS=$ORIG_IFS
 
# ------------------------------------------
# Ends
# ------------------------------------------
log_msg "Exit script with no error."
exit "${E_NOERROR}"
