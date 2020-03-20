FROM ose-cli:v3.11
MAINTAINER openshift@essiprojects.com

ENV IMAGE_SCRIPTS_HOME /opt/pvc-backup
ENV USER_PASS='Backup123'

RUN \
  mkdir $IMAGE_SCRIPTS_HOME && \
  groupadd -g 65534 nfsnobody && \
  groupadd -g 10001 backup && \
  useradd -r -u 10001 -g backup --home-dir $IMAGE_SCRIPTS_HOME backup && \
  groupadd -g 10002 rsyncuser && \
  useradd -r -u 10002 -g rsyncuser -G nfsnobody --home-dir $IMAGE_SCRIPTS_HOME rsyncuser && \
  echo "${USER_PASS}" | passwd rsyncuser --stdin

# Update the image with the latest packages (recommended)
RUN yum update -y && yum clean all

# Install rsync tool
RUN yum install rsync -y && yum clean all

COPY backup.sh $IMAGE_SCRIPTS_HOME/

RUN \  
  chmod u+s /usr/bin/sed && \
  chmod +x $IMAGE_SCRIPTS_HOME/backup.sh 

USER 10001
WORKDIR $IMAGE_SCRIPTS_HOME

ENTRYPOINT ["/bin/bash", "backup.sh"]
