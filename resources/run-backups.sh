#!/bin/bash
MAIL_FILE=/tmp/mail.txt
RESULT=OK

function echo_date
{
  echo "$(date -Iseconds) $1"
}

> $MAIL_FILE

while read type ns svc port user pass db
do
  out_dir=$BACKUP_DIR/$type/$ns.$svc
  mkdir -p $out_dir
  out_file=$out_dir/$(date +%y%m%d_%H%M).sql.bz2
  log_file=$out_dir/$(basename $out_file .sql.bz2).log

  echo_date "Running backup for $user@$svc.$ns" | tee -a $MAIL_FILE
  find $out_dir -mtime +$RETENTION_DAYS -type f -exec rm -rf {} \;
  case $type in
  mysql)
    if [ "$db" ]
    then
      cmd="mysqldump"
      args="--verbose --add-drop-database --add-drop-table --routines --triggers -h $svc.$ns -P $port -u $user -p$pass $db"
    else
      cmd="mysqldump"
      args="--verbose --add-drop-database --add-drop-table --routines --triggers -h $svc.$ns -P $port -u $user -p$pass --all-databases"
    fi
    ;;
  postgresql)
    export PGPASSWORD="$pass"
    export PGOPTIONS="-c statement_timeout=0"
    if [ "$db" ]
    then
      cmd="pg_dump"
      args="--verbose --clean --no-password -U $user -h $svc.$ns -p $port -d $db"
    else
      cmd="pg_dumpall"
      args="--verbose --clean --no-password -U $user -h $svc.$ns -p $port"
    fi
    ;;
  esac
  
  $cmd $args 2> $log_file | bzip2 > $out_file
  if [ ${PIPESTATUS[0]} -eq 0 ]
  then
    echo_date "OK - $(grep -c -e "dumping contents of table" -e "Retrieving table structure" $log_file) tables dumped" | tee -a $MAIL_FILE
  else
    echo_date ERROR
    echo ERROR >> $MAIL_FILE
    cat $log_file | tee -a $MAIL_FILE
    RESULT=ERROR
  fi
done < <(egrep '^(mysql|postgresql)' $CONFIG_DIR/$CONFIG_FILE)

echo -e "\nProcedimiento: http://confluence.uoc.edu/pages/viewpage.action?pageId=66850139" >> $MAIL_FILE

sed "1iSubject: ($RESULT) Backups BD Openshift\
\nTo: <$MAIL_DEST>\
\nFrom: Backups BD <$MAIL_FROM>\
\n" $MAIL_FILE | msmtp --host=$MAIL_RELAY --from=$MAIL_FROM $MAIL_DEST
