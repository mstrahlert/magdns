#!/bin/sh
#
# 21/03/2010: magnus@strahlert.net
#             first version, hardcoded for one domain
# 25/03/2010: magnus@strahlert.net
#             second version, now more general 
################################################################

ADM="mst Strahlert.net"
ADMMAIL=magnus.strahlert.net
DBHOST=dns.home.strahlert.net
NSHOSTS=dns.home.strahlert.net

DB=/usr/local/etc/namedb/master
HOSTS=${DB}/../HOSTS.TXT

################################################################
#

if [ ! -f ${HOSTS} ]; then
  echo "${HOSTS} doesn't exist"
  exit 1
fi

make_serial() {
  if [ $# != 1 ]; then
    echo "Error: Wrong arguments to make_serial()"
    return 1
  fi

  # Generate serial
  NEWSERIAL=`date +%Y%m%d`00
  if [ -r "${DB}/${1}.serial" ]; then
    OLDSERIAL=`cat ${DB}/${1}.serial`
  else
    OLDSERIAL=0
  fi

  if [ $NEWSERIAL -le $OLDSERIAL ]; then
    NEWSERIAL=$((OLDSERIAL + 1))
  fi

  echo $NEWSERIAL > ${DB}/${1}.serial
}

make_soa() {
  if [ $# != 1 ]; then
    echo "Error: Wrong arguments to make_soa()"
    return 1
  fi

  if [ -z "`echo $1|sed -n 's/[a-z0-9.-]*/&/p'`" ]; then
    echo "Error: Argument to make_soa() doesn't match a FQDN/IP"
    return 1
  fi

  if [ ! -r ${DB}/${1}.load ]; then
    touch ${DB}/${1}.load
  fi

  make_serial $1

cat > ${DB}/${1}.soa << END-OF-SOA-1
;
; ${1}   Serial: ${NEWSERIAL}
;
;       Last update: `date`
;       Administrator: ${ADM} <`echo ${ADMMAIL} | sed -e 's/\./@/'`>
;
\$TTL 86400

@               IN      SOA     ${DBHOST}. ${ADMMAIL}. (
                           ${NEWSERIAL}           ; Serial
                                 1800           ; Refresh 30 Min
                                  900           ; Retry   15 Min
                               604800           ; Expire   7 Days
                                86400)          ; TTL      1 Day

\$INCLUDE $DB/${1}.load
\$INCLUDE $DB/${1}-hosts
END-OF-SOA-1
}

# Loop through ${HOSTS}
while IFS=: read host iaddr name mtype os protocol comment; do
  # Trim whitespaces
  host=`echo $host|awk '{printf "%s\n", $1}'` 
  iaddr=`echo $iaddr|awk '{printf "%s\n", $1}'`
  name=`echo $name|awk '{printf "%s\n", $1}'`
  mtype=`echo $mtype|awk '{printf "%s\n", $1}'`
  os=`echo $os|awk '{printf "%s\n", $1}'`
  protocol=`echo $protocol|awk '{printf "%s\n", $1}'`
  comment=`echo $comment|awk '{printf "%s\n", $1}'`

  # If first field isn't DOMAIN or HOST then there's an error
  # in the indata on that line, perhaps a comment.
  if [ $host = "DOMAIN" ]; then
    fcheck=0
    dname=${iaddr}
  elif [ $host = "HOST" ]; then
    if [ "X${mtype}" = "X" ]; then
      mtype="UNKNOWN"
    fi

    if [ "X${os}" = "X" ]; then
      os="UNKNOWN"
    fi

    # Split the ip address into its respective parts
    st=`echo $iaddr|cut -d. -f1`
    nd=`echo $iaddr|cut -d. -f2`
    rd=`echo $iaddr|cut -d. -f3`
    th=`echo $iaddr|cut -d. -f4`

    # dname="`echo $name|sed -n 's/[a-z0-9-]*\.\([a-z0-9-]*\)\..*/\1/p'`"

    # Generate filename for forward and reverse
    FORWARD=${DB}/${dname}-hosts
    REVERSE=${DB}/${rd}.${nd}.${st}-hosts

    # ${HOSTS} hasn't been changed. Check must be here
    # since $FORWARD can be variable if several domainnames
    # have been defined
    if [ "${fcheck}" = "0" ] && [ ${HOSTS} -ot $FORWARD ]; then
      continue
    fi

    fcheck=1

    # If first iteration, then clean up output files
    if [ -z "`echo ${forwards}|grep ${dname}`" ]; then
    #if [ "X${output}" = "X" ]; then
    #  echo "Making into ${DB}"
      echo "Generating SOA for ${dname}"

      cat /dev/null > $FORWARD
      #cat /dev/null > $REVERSE

      make_soa ${dname}
      #make_soa ${rd}.${nd}.${st}
      forwards="${dname} ${forwards}"
    fi
    #output=1

    # Use word-grep since the reverse can be part of an already
    # existing larger reverse (ie 0.168.192 is part of 100.168.192)
    if [ -z "`echo ${reverses}|grep -w ${rd}.${nd}.${st}`" ]; then
      echo "Generating SOA for ${rd}.${nd}.${st}"

      if [ ! -f ${REVERSE}.lock ]; then
        cat /dev/null > $REVERSE
        touch ${REVERSE}.lock
      fi

      make_soa ${rd}.${nd}.${st}
      reverses="${rd}.${nd}.${st} ${reverses}"
    fi

#    echo "n1: \"${n1}\", iaddr: ${iaddr}, name: ${name}"
    # Loop through the name(s) of the record
    export IFS=, ; n1=""; for n in ${name}; do 
#      echo "n1: \"${n1}\" n: \"${n}\""
      if [ "X${n1}" = "X" -a "X${n}" != "X" ]; then 
        printf "%-30s IN       A       %s\n" ${n}.${dname}. ${iaddr} >> ${FORWARD}
        printf "%-30s IN       HINFO   \"%s\" \"%s\"\n" "" ${mtype} ${os}  >> ${FORWARD}
        printf "%-30s IN       PTR     %s\n" ${th}.${rd}.${nd}.${st}.in-addr.arpa. ${n}.${dname}. >> ${REVERSE}

        # Store the first name in a variable. This is the A record
        # Any following names are CNAME records
        n1=${n}
      else
        if [ "X${n1}" = "X" -a "X${n}" != "X" ]; then
          printf "%-30s IN       CNAME   %s\n" ${n} ${n}.${dname}. >> ${FORWARD}
        elif [ "X${n1}" != "X" ]; then
          printf "%-30s IN       CNAME   %s\n" ${n}.${dname}. ${n1}.${dname}. >> ${FORWARD}
        fi
      fi
    done

    n1=""
  fi 
  IFS=:
done < ${HOSTS}

if [ -f ${REVERSE}.lock ]; then
  rm ${REVERSE}.lock
fi
