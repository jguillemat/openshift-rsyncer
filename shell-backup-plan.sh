#!/bin/bash
# 
# Descrition:           
#   Script para la sincronización de un conjunto de volumenes de glusterfs (pv/pvc) hacia un servidor remoto con
#   acceso ssh/rsync.
#   El servidore remoto (SSH_SERVER) deberá poder montar el servicio NFS localmente.
#
#   Configuracion basado en un fichero de configuración:
#    {
#	    "REPLICA_VOLUMES": [ {
#		    "NAMESPACE": "pvc-backuper",
#		    "PVC": "data-pvc",
#		    "PV": "pvc-0e48b67d-6a98-11ea-a00e-001a4a461c22",
#		    "PVC_GLUSTER_MOUNT_DATA": "vol_4619cd02f4cf514517c6043e33008f3d",
#		    "PVC_REPLICA": "replica-pvc"
#	    }, {
#		    "NAMESPACE": "pvc-backuper",
#		    "PVC": "data-pvc",
#		    "PV": "pvc-0e48b67d-6a98-11ea-a00e-001a4a461c22",
#		    "PVC_GLUSTER_MOUNT_DATA": "vol_4619cd02f4cf514517c6043e33008f3d",
#		    "PVC_REPLICA": "replica-pvc"
#	    }
#	    ], 
#	    "CONFIGURATION": {
#		    "SSH_SERVER": "ocp-nexica-bastion.uoc.es",
#           "REMOTE_NFS_ENDPOINT": "vdm-oscont.uoc.es:/PRO_openshift_repo/",
#		    "REMOTE_REPLICA_DIR": "/mnt/nfs/",
#		    "LOCAL_DATA_DIR": "/tmp/nfs/",
#		    "BACKUP_RSYNC_OPTIONS": "-avz"
#	    }
#    } 

# EXIT ERRORS
readonly E_NOSYNCPLAN=255         # CANNOT GET SYNC PLAN FILE
readonly E_SYNCPLAN_EMPTY=254     # CANNOT GET SYNC PLAN DATA
readonly E_NONAMESPACE=253         # CANNOT GET NAMESPACE
readonly E_CANNOT_MOUNT_GLUSTER=252 # CANNOT MOUNT GLUSTERVOL INTO LOCAL DIR
readonly E_CANNOT_MOUNT_REMOTE=251   # CANNOT MOUNT REMOTE NFS ENDPOINT
readonly E_NOSSH_CONNECTION=250     # Cannot establish a SSH connection
readonly E_RSYNC_ERROR=249     # Cannot establish a SSH connection
readonly E_NOERROR=0              # ALL IT'S OK

# Configure rsync into PATH
PATH=$PATH:/usr/bin/:.
export PATH

# --------------------------------------
# GLOBAL VARIABLES with DEFAULTS
# --------------------------------------
g_result_code=OK
g_ssh_server=""
g_BACKUP_RSYNC_OPTIONS="-auvz"
g_local_data_dir="/mnt/test-glusterfs"
g_remote_replica_dir="/mnt/test-nfs"
MAIL_RELAY="smpt.uoc.edu"
MAIL_FROM=""
MAIL_DEST=""

# --------------------------------------
# FUNCTIONS
# --------------------------------------

# --------------------------------------
#
function log_msg() {
    echo "$(date +%Y%m%d%H%M) - $@"
    echo -e "$(date +%Y%m%d%H%M) - $@" 1>&2 >> $SYNC_LOG_FILE
}

function error_msg() {
    g_result_code=ERROR

    echo "$(date +%Y%m%d%H%M) - $@" 1>&2;
    echo -e "$(date +%Y%m%d%H%M) - $@" >> $SYNC_LOG_FILE
}

function end_process() 
{
    send_mail
    exit "$1"
}

function send_mail() {

    sed "1iSubject: ($g_result_code) Syncrhonize PV Data from Castelldefels to Nexica\
    \nTo: <$MAIL_DEST>\
    \nFrom: Backup PV Data <$MAIL_FROM>\
    \n" $SYNC_LOG_FILE | msmtp --host=$MAIL_RELAY --from=$MAIL_FROM $MAIL_DEST
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
        end_process "$E_NOSSH_CONNECTION"
    fi
    return "0";
}

function execute_remote() {
    # log_msg "Executing SSH: '$@' "
    ssh ${g_ssh_server} "$p_ssh_options" "$@"
}


# --------------------------------------
# BACKUP PV DATA METHOD
# --------------------------------------

function synchronize_data() {

    log_msg "Entering into synchronize_data ${*} ..."
    local p_namespace="$1"
    local p_pvc="$2"
    local p_mount_data="$3"
    local p_pvc_replica="$4"
 
    log_msg "Checking Namespace '${p_namespace}' ..."
    if [[ "${p_namespace}" == "" ]]; then
        error_msg "ERROR: NAMESPACE not specified. Exiting method."
        return "${E_NONAMESPACE}"
    fi        
        
    log_msg " ------------------------------------------------"
    log_msg " Mount GlusterVol (SOURCE) into local dir"
    log_msg " ------------------------------------------------"

    local local_dir=${g_local_data_dir%/}
    local source_dir="${local_dir}/${p_namespace}/${p_pvc}"
    [[ "${source_dir}" != */ ]] && source_dir="${source_dir}/"

    log_msg "Check local directory ${source_dir}."
    if [ -d "$source_dir" ]; then
        log_msg "Local directory already ${source_dir} exist."
    else 
        log_msg "Creating local directory ${source_dir}."
        mkdir -p "${source_dir}"
    fi

    gluster_mount_dir=${p_mount_data%/}
    log_msg "Check local mount point into ${gluster_mount_dir}."
    if mount | grep ${gluster_mount_dir} > /dev/null; then
         log_msg "GlusterVol already mounted locally"
    else 
        log_msg "Mounting GlusterVol '${p_mount_data}' into '${source_dir}' "
        if mount -t glusterfs ${p_mount_data} ${source_dir} -o ro  > /dev/null; then
            log_msg "GlusterVol mounted locally"
        else 
            error_msg "ERROR Mounting GlusterVol '${p_mount_data}' into '${source_dir}'. Exiting method"
            return "${E_CANNOT_MOUNT_GLUSTER}"
        fi
    fi

    log_msg " ------------------------------------------------"
    log_msg " Mount NFS Endpoint in remote server"
    log_msg " ------------------------------------------------"

    remote_mount_dir=${g_remote_replica_dir%/}
    log_msg "REMOTE: Check remote mount point into ${remote_mount_dir}."
    if execute_remote "mount | grep $remote_mount_dir > /dev/null 2>&1"
    then
        log_msg "REMOTE: NFS Endpoint already mounted in ${g_remote_replica_dir}."
    else
        log_msg "REMOTE: NFS Endpoint isn't mounted. Creating."
        log_msg "REMOTE: Check remote mount directory exist in ${g_remote_replica_dir}."
        if execute_remote "test -d $g_remote_replica_dir > /dev/null 2>&1"
        then
            log_msg "REMOTE: Remote mount directory already exist."
        else
            log_msg "REMOTE: Creating remote mount directory '${g_remote_replica_dir}'."
            execute_remote "mkdir -p ${g_remote_replica_dir}"
        fi    
        log_msg "REMOTE: Mounting NFS in '${g_remote_replica_dir}' into remote server"
        if execute_remote "mount -t nfs ${p_remote_nfs_endpoint} ${g_remote_replica_dir}"
        then
            log_msg "REMOTE: Remote NFS endpoint mounted successfully."
        else
            error_msg "REMOTE: ERROR Mounting NFS '${p_remote_nfs_endpoint}' into '${g_remote_replica_dir}'. Exiting method"
            return "${E_CANNOT_MOUNT_REMOTE}"
        fi 
    fi

    log_msg "# -----------------------------------------------------------------"
    log_msg "# Create (if no exist) replica directory into remote server"
    # -----------------------------------------------------------------""
    local replica_dir=""
    [[ "${g_remote_replica_dir}" != */ ]] && g_remote_replica_dir="${g_remote_replica_dir}/"
    namespace_dir="${g_remote_replica_dir}${p_namespace}/"

    if execute_remote "test -d $namespace_dir > /dev/null 2>&1"
    then
        log_msg "REMOTE: Remote namespace directory already exist."
    else
        log_msg "REMOTE: Creating remote mount directory '${g_remote_replica_dir}'."
        log_msg "Creating remote namespace directory '${namespace_dir}'."
        execute_remote "mkdir -p ${namespace_dir}"
        execute_remote "chown nfsnobody:nfsnobody ${namespace_dir}"
    fi    

    [[ "${p_pvc_replica}" != */ ]] && replica_dir="${g_remote_replica_dir}${p_namespace}/${p_pvc_replica}/"
    [[ "${p_pvc_replica}" == */ ]] && replica_dir="${g_remote_replica_dir}${p_namespace}/${p_pvc_replica}"
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

    log_msg "Native RSYNC starts for PVC '${p_pvc}' from DIR '${source_dir}' from NAMESPACE '${p_namespace}' into '${replica_dir}' with rsync options '${g_BACKUP_RSYNC_OPTIONS}' ..."
    rsync ${g_BACKUP_RSYNC_OPTIONS} ${source_dir} ${g_ssh_server}:/${replica_dir}
    if [ $? == 0 ]; then
        log_msg "Native RSYNC finished successfully"
    else
        error_msg "ERROR - Some error succeded in rsync process"
        return "${E_RSYNC_ERROR}"
    fi
 
    # ---------------------------------------------
    # Umount Gluster Volume localy
    # ---------------------------------------------
    # log_msg "Unmounting GlusterVol from '${source_dir}' "
    # umount ${source_dir} --force

    # ---------------------------------------------
    # Umount Remote NFS Replica dir
    # ---------------------------------------------
    # log_msg "Umounting NFS from '${g_remote_replica_dir}' into remote server"
    # execute_remote "umount ${g_remote_replica_dir} --force"
    
    log_msg "End of Volume synchronization"
    return "$E_NOERROR";
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
SYNC_LOG_FILE="${LOG_DIR}/synchronize_data_execution_$(date +%Y%m%d%H%M).log"

# init log file
> $SYNC_LOG_FILE

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
    end_process "${E_NOSYNCPLAN}" 
fi
if [[ ! -s "$PLAN_FILE" ]]; then
    error_msg "ERROR - Not sync plan data into '${PLAN_FILE}' "
    end_process "${E_SYNCPLAN_EMPTY}" 
fi
log_msg "Getted PLAN_FILE = '${PLAN_FILE}'."

# ------------------------------------------
# Get SSH_SERVER option
# ------------------------------------------
log_msg "Reading SSH_SERVER parameter ..."
g_ssh_server="${SSH_SERVER}"
log_msg "Checking SSH_SERVER ${g_ssh_server}..."
if [[ "${g_ssh_server}" == "" ]]; then
    g_ssh_server="$( jq -r '.CONFIGURATION.SSH_SERVER' ${PLAN_FILE} )"
fi
log_msg "Readed SSH_SERVER '${g_ssh_server}'"


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
    end_process "${E_NOSSH_CONNECTION}"
fi

# ------------------------------------------
# Get REMOTE_NFS_ENDPOINT option
# ------------------------------------------
log_msg "Reading REMOTE_NFS_ENDPOINT parameter ..."
p_remote_nfs_endpoint="${REMOTE_NFS_ENDPOINT}"
if [[ "${p_remote_nfs_endpoint}" == "" ]]; then
    p_remote_nfs_endpoint="$( jq -r '.CONFIGURATION.REMOTE_NFS_ENDPOINT' ${PLAN_FILE} )"
fi
log_msg "Readed REMOTE_NFS_ENDPOINT '${p_remote_nfs_endpoint}'"

# ------------------------------------------
# Get REMOTE_REPLICA_DIR option
# ------------------------------------------
log_msg "Reading REMOTE_REPLICA_DIR parameter ..."
g_remote_replica_dir="${REMOTE_REPLICA_DIR}"
if [[ "${g_remote_replica_dir}" == "" ]]; then
    g_remote_replica_dir="$( jq -r '.CONFIGURATION.REMOTE_REPLICA_DIR' ${PLAN_FILE} )"
fi
log_msg "Readed REMOTE_REPLICA_DIR '${g_remote_replica_dir}'"

# ------------------------------------------
# Get LOCAL_DATA_DIR option
# ------------------------------------------
log_msg "Reading LOCAL_DATA_DIR parameter ..."
g_local_data_dir="${LOCAL_DATA_DIR}"
if [[ "${g_local_data_dir}" == "" ]]; then
    g_local_data_dir="$( jq -r '.CONFIGURATION.LOCAL_DATA_DIR' ${PLAN_FILE} )"
fi
log_msg "Readed LOCAL_DATA_DIR '${g_local_data_dir}'"
 
# ------------------------------------------
# Get RSYNC option
# ------------------------------------------
log_msg "Reading BACKUP_RSYNC_OPTIONS parameter ..."
g_BACKUP_RSYNC_OPTIONS="${BACKUP_RSYNC_OPTIONS}"
if [[ "${g_BACKUP_RSYNC_OPTIONS}" == "" ]]; then
    g_BACKUP_RSYNC_OPTIONS="$( jq -r '.CONFIGURATION.BACKUP_RSYNC_OPTIONS' ${PLAN_FILE} )"
fi
log_msg "Readed BACKUP_RSYNC_OPTIONS '${g_BACKUP_RSYNC_OPTIONS}'"

 
# ------------------------------------------
# Get MAIL PARAMETERS
# ------------------------------------------
g_mail_server="${MAIL_RELAY}"
if [[ "${g_mail_server}" == "" ]]; then
    g_mail_server="$( jq -r '.CONFIGURATION.MAIL_RELAY' ${PLAN_FILE} )"
fi
log_msg "Readed MAIL_RELAY: '${g_mail_server}'"
g_mail_from="${MAIL_FROM}"
if [[ "${g_mail_from}" == "" ]]; then
    g_mail_from="$( jq -r '.CONFIGURATION.MAIL_FROM' ${PLAN_FILE} )"
fi
log_msg "Readed MAIL_FROM: '${g_mail_from}'"
g_mail_dest="${MAIL_DEST}"
if [[ "${g_mail_dest}" == "" ]]; then
    g_mail_dest="$( jq -r '.CONFIGURATION.MAIL_DEST' ${PLAN_FILE} )"
fi
log_msg "Readed MAIL_DEST: '${g_mail_dest}'"


# ------------------------------------------
# Process plan data 
# ------------------------------------------
log_msg "Starting processing sync plan file ..."

list=$(cat "$PLAN_FILE" | jq -r '.REPLICA_VOLUMES[]|"\(.NAMESPACE) \(.PVC) \(.PVC_GLUSTER_MOUNT_DATA) \(.PVC_REPLICA)"')

ORIG_IFS=$IFS        # Save the original IFS
LINE_IFS=$'\n'$'\r'  # For splitting input into lines
FIELD_IFS=$'\n';     # For splitting lines into fields
IFS=$LINE_IFS
for line in $list; do
    echo " Processing LINE=${line}"
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
                error_msg "ERROR - Some error succeded in synchronize_data (LINE: ${line} )"
            fi
        else
            error_msg "ERROR - Some required parameter not speciefied (LINE: ${line} )"
        fi
        
    done
    IFS=$LINE_IFS
done
IFS=$ORIG_IFS

# ------------------------------------------
# Sends Mail
# ------------------------------------------
# log_msg "Sending Mail"
send_mail

# ------------------------------------------
# Ends
# ------------------------------------------
log_msg "Exit script with no error."
exit "${E_NOERROR}"