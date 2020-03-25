#!/bin/bash
# 
# Descrition:           
#   Script para la sincronización de un conjunto de volumenes de glusterfs (pv/pvc) hacia un servidor remoto con
#   acceso ssh/rsync.
#   El servidore remote (REMOTE_SERVER) debe poder montar el servicio NFS en local.
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
#		    "REMOTE_SERVER": "ocp-nexica-bastion.uoc.es",
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
readonly E_NOPODNAME=252          # CANNOT GET POD NAME
readonly E_NOVOLUME=251           # POD_VOLUME not specified
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
log_msg() {
		echo "$(date +%Y%m%d%H%M) - $@"
}

error_msg() {
		echo "$(date +%Y%m%d%H%M) - $@" 1>&2;
}
 
# --------------------------------------
# SYNCHRONIZE METHOD
# --------------------------------------

synchronize_data () {

    log_msg "Entering into synchronize_data ${*} ..."
    local p_namespace="$1"
    local p_pvc="$2"
    local p_pv="$3"
    local p_mount_data="$4"
    local p_pvc_replica="$5"

	echo " p_namespace=$p_namespace"
	echo " p_pvc=$p_pvc"
	echo " p_pv=$p_pv"
	echo " p_mount_data=$p_mount_data"
	echo " p_pvc_replica=$p_pvc_replica"   

           
    log_msg "Checking Namespace '${p_selector}' ..."
    if [[ "${p_namespace}" == "" ]]; then
        error_msg "ERROR: NAMESPACE not specified. Exit."
        return "${E_NONAMESPACE}"
    fi        
        
    # --------------------------
    # Mount PVC locally
    # --------------------------
    # Check final slash
    local source_dir=""
    [[ "${p_local_data_dir}" != */ ]] && p_local_data_dir="${p_local_data_dir}/"
    [[ "${p_pvc}" != */ ]] && source_dir="${p_local_data_dir}${p_namespace}/${p_pvc}/"
    [[ "${p_pvc}" == */ ]] && source_dir="${p_local_data_dir}${p_namespace}/${p_pvc}"
    
    log_msg "Creating local directory ${source_dir}."
    mkdir -p "${source_dir}"

    log_msg "Mounting GlusterVol locally into "
    mount -t fuse.glusterfs ${p_mount_data} ${source_dir}

    # ---------------------------------------------
    # Mount NFS Endpoint into remote server
    # ---------------------------------------------
    log_msg "Creating remote mount directory '${p_remote_replica_dir}'."
    ssh ${p_remote_server} mkdir -p "${p_remote_replica_dir}"

    log_msg "Mounting NFS in '${p_remote_replica_dir}' into remote server"
    ssh ${p_remote_server} mount -t nfs ${p_remote_nfs_endpoint} ${p_remote_replica_dir}

    # -----------------------------------------------------------------
    # Create (if no exist) replica directory into remote server
    # -----------------------------------------------------------------
    local replica_dir=""
    [[ "${p_remote_replica_dir}" != */ ]] && p_remote_replica_dir="${p_remote_replica_dir}/"
    namespace_dir="${p_remote_replica_dir}${p_namespace}/"

    log_msg "Creating remote namespace directory '${namespace_dir}'."
    ssh ${p_remote_server} mkdir -p "${namespace_dir}"
    ssh ${p_remote_server} chown nfsnobody:nfsnobody "${namespace_dir}"

    [[ "${p_pvc_replica}" != */ ]] && replica_dir="${p_remote_replica_dir}${p_namespace}/${p_pvc_replica}/"
    [[ "${p_pvc_replica}" == */ ]] && replica_dir="${p_remote_replica_dir}${p_namespace}/${p_pvc_replica}"

    log_msg "Creating remote pvc replica directory '${replica_dir}'."
    ssh ${p_remote_server} mkdir -p "${replica_dir}"
    ssh ${p_remote_server} chown nfsnobody:nfsnobody "${replica_dir}"


    # --------------------------
    # Start rsync data    
    # --------------------------

    log_msg "Start NATIVE RSYNC from DIR ${source_dir} of POD ${p_name} from NAMESPACE ${project} into ${replica_dir} with rsync options '${RSYNC_OPTIONS}' ..."
    rsync ${RSYNC_OPTIONS} ${source_dir} ${p_remote_server}:/${replica_dir}

#    sleep 60;
    log_msg "End of Volume synchronization"
}


## ------------------------------------------ ##
## ------------------------------------------ ##
##                                            ## 
##    Main method                             ##
##                                            ##
## ------------------------------------------ ##
## ------------------------------------------ ##

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

# ------------------------------------------
# Get REMOTE_SERVER option
# ------------------------------------------
log_msg "Reading REMOTE_SERVER parameter ..."
p_remote_server="${REMOTE_SERVER}"

log_msg "Checking REMOTE_SERVER ${p_remote_server}..."
if [[ "${p_remote_server}" == "" ]]; then
    p_remote_server="$( jq -r '.CONFIGURATION.REMOTE_SERVER' ${PLAN_FILE} )"
    log_msg "Readed REMOTE_SERVER '${p_remote_server}'"
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
while read p_namespace p_pvc p_pv p_mount_data p_pvc_replica; 
do
    echo " ------------------------------------------------"
    echo " Reading JSON entry ..."
    echo " ------------------------------------------------"
	echo " p_namespace=$p_namespace"
	echo " p_pvc=$p_pvc"
	echo " p_pv=$p_pv"
	echo " p_mount_data=$p_mount_data"
	echo " p_pvc_replica=$p_pvc_replica"

	synchronize_data "${p_namespace}" "${p_pvc}" "${p_pv}" "${p_mount_data}" "${p_pvc_replica}"
	
done < <(jq -r '.SOURCE_VOLUMES[]|"\(.NAMESPACE) \(.PVC) \(.PV) \(.MOUNT_DATA) \(.PVC_REPLICA)"' ${PLAN_FILE})


log_msg "Exit script with no error."
exit "${E_NOERROR}"
