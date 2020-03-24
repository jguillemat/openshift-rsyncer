FROM ose-cli:v3.11
MAINTAINER openshift@essiprojects.com

ENV HOME /opt/app-root
ENV SCRIPTS_HOME /opt/app-root
ENV USER_PASS='Redhat01'
ENV SYNC_PLAN_PATH /opt/app-root/conf

LABEL io.k8s.description="Openshift OC rsync tool" \
      io.k8s.display-name="rsyncer-0.0.1" \
      io.openshift.tags="rsyncer,0.0.1"

# Update the image with the latest packages (recommended)
RUN yum update -y && yum clean all && rm -rf /var/cache/yum/*

# Install rsync, gluster & nfs clients
RUN yum install rsync tar glusterfs-fuse nfs-utils -y && yum clean all && rm -rf /var/cache/yum/*

RUN \
  mkdir $SCRIPTS_HOME && mkdir $SYNC_PLAN_PATH && \
  groupadd -g 65534 nfsnobody && \
  groupadd -g 10001 backup && \
  useradd -r -u 10001 -g backup -G wheel --home-dir $SCRIPTS_HOME backup && \
  groupadd -g 10002 rsyncuser && \
  useradd -r -u 10002 -g rsyncuser -G nfsnobody --home-dir $SCRIPTS_HOME rsyncuser && \
  echo "${USER_PASS}" | passwd rsyncuser --stdin

COPY backup.sh $SCRIPTS_HOME/
COPY sync-plan.json $SYNC_PLAN_PATH/

chmod u+s /usr/bin/sed && \
 chmod +x $SCRIPTS_HOME/backup.sh 

# USER 10001
USER root

WORKDIR $SCRIPTS_HOME
ENTRYPOINT ["/bin/bash", "backup.sh"]
