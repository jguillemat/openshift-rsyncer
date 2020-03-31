FROM openshift/ose-cli:latest
MAINTAINER openshift@essiprojects.com

ENV HOME="/opt/app-root" \
  SCRIPTS_HOME="/opt/app-root" \
  SYNC_PLAN_PATH="/opt/app-root/conf" \
  LOG_PATH="/opt/app-root/logs" \
  PATH=$PATH:$SCRIPTS_HOME

LABEL io.k8s.description="Openshift PV rsync tool" \
      io.k8s.display-name="rsyncer-0.0.1" \
      io.openshift.tags="rsyncer,0.0.1"

# Update the image with the latest packages (recommended)
RUN yum update -y && \
  yum clean all && \
  rm -rf /var/cache/yum/*

# Install rsync, gluster & nfs clients
RUN yum install -y rsync tar glusterfs-fuse nfs-utils iputils bind-utils && \
  yum clean all && \
  rm -rf /var/cache/yum/*

# Prepare directories
RUN \
  mkdir $SCRIPTS_HOME && \
  mkdir $SYNC_PLAN_PATH && \
  mkdir $LOGS_PATH && \
  groupadd -g 10001 backup && \
  useradd -r -u 10001 -g backup -G wheel --home-dir $SCRIPTS_HOME backup

# RUN \
#  wget -O $SCRIPTS_HOME/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64

# Copy scripts & binary files
COPY backup.sh $SCRIPTS_HOME/
COPY backup-plan.sh $SCRIPTS_HOME/
COPY conf/*.json $SYNC_PLAN_PATH/
COPY resources/jq $SCRIPTS_HOME/

# Correct permissions
RUN \
 chmod u+s /usr/bin/sed && \
 chmod +x $SCRIPTS_HOME/*.sh && \
 chmod 755 $LOGS_PATH && \
 chmod +x $SCRIPTS_HOME/jq 

# USER 10001

# Need execute as "root" because we want to mount NFS endpoints internally
USER root

WORKDIR $SCRIPTS_HOME
ENTRYPOINT ["/bin/bash", "oc-backup.sh"]
