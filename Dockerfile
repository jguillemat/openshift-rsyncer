FROM ose-cli:v3.11
MAINTAINER openshift@essiprojects.com

ENV HOME /opt/app-root
ENV SCRIPTS_HOME /opt/app-root
ENV USER_PASS='Redhat01'

LABEL io.k8s.description="Openshift OC rsync tool" \
      io.k8s.display-name="rsyncer-0.0.1" \
      io.openshift.tags="rsyncer,0.0.1" \

RUN \
  mkdir $SCRIPTS_HOME && \
  groupadd -g 65534 nfsnobody && \
  groupadd -g 10001 backup && \
  useradd -r -u 10001 -g backup --home-dir $SCRIPTS_HOME backup && \
  groupadd -g 10002 rsyncuser && \
  useradd -r -u 10002 -g rsyncuser -G nfsnobody --home-dir $SCRIPTS_HOME rsyncuser && \
  echo "${USER_PASS}" | passwd rsyncuser --stdin

# Update the image with the latest packages (recommended)
RUN yum update -y && yum clean all && rm -rf /var/cache/yum/*

# Install rsync tool
RUN yum install rsync tar -y && yum clean all && rm -rf /var/cache/yum/*

COPY backup.sh $SCRIPTS_HOME/

RUN \  
  chmod u+s /usr/bin/sed && \
  chmod +x $SCRIPTS_HOME/backup.sh 

USER 10001
WORKDIR $SCRIPTS_HOME

ENTRYPOINT ["/bin/bash", "backup.sh"]
