#!/bin/sh

IFREGEXP="eth.*"

APIKEY="---enter-your-API-key-here----"
ID="6262"

TITLE="Internet usage"
DESCR="Internet usage counters"
WEBSITE="http://wiki.version6.net/PachubeNetworkUsage"

LOCNAME="Lonely island in the middle of nowhere"
LOCLAT="39.7113927178886"
LOCLON="-31.1134557717014"

###########################################################################
#
# No need to edit anything after that line
#

URL="http://www.pachube.com/api/feeds/${ID}.xml"
CREATOR="http://wiki.version6.net/PachubeNetworkUsage"
TMPFILE="/tmp/pachube_ethdata.dat"

TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TS="$(date +%s)"

NEWDATA=$(cat /proc/net/dev \
| tr : ' ' \
| awk '
      /^'${IFREGEXP}' / {
              bin += $2 * 8;
              bout += $10 * 8;
      }
      END {
              printf("%.0f,%.0f\n", bin, bout);
      }')

if [ ! -f "$TMPFILE" ]; then
      echo "${TS}:${NEWDATA}" > $TMPFILE
      exit
fi

NEWBI="${NEWDATA%,*}"
NEWBO="${NEWDATA#*,}"

OLDDATA="$(cat $TMPFILE)"
echo "${TS}:${NEWDATA}" > $TMPFILE

OLDTS="${OLDDATA%:*}"
OLDDATA="${OLDDATA#*:}"
OLDBI="${OLDDATA%,*}"
OLDBO="${OLDDATA#*,}"

SECONDS=$(($TS - $OLDTS))

[ "$SECONDS" -le 0 ] && exit

BI=$(awk "END { printf(\"%.3f\", ($NEWBI - $OLDBI) / $SECONDS / 1000000) }" < /dev/null)
BO=$(awk "END { printf(\"%.3f\", ($NEWBO - $OLDBO) / $SECONDS / 1000000) }" < /dev/null)

XMLDATA="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<eeml xmlns=\"http://www.eeml.org/xsd/005\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" version=\"5\" xsi:schemaLocation=\"http://www.eeml.org/xsd/005 http://www.eeml.org/xsd/005/005.xsd\">
  <environment updated=\"${TIME}\" id=\"${ID}\" creator=\"${CREATOR}\">
    <title>${TITLE}</title>
    <feed>${URL}</feed>
    <status>live</status>
    <description>${DESCR}</description>
    <website>${WEBSITE}</website>
    <location domain=\"physical\" exposure=\"indoor\" disposition=\"fixed\">
      <name>${LOCNAME}</name>
      <lat>${LOCLAT}</lat>
      <lon>${LOCLON}</lon>
    </location>
    <data id=\"0\">
      <tag>internet</tag>
      <tag>bandwidth</tag>
      <tag>incoming</tag>
      <value minValue=\"0\">${BI}</value>
      <unit type=\"contextDependentUnits\" symbol=\"Mbps\">Megabits per second</unit>
    </data>
    <data id=\"1\">
      <tag>internet</tag>
      <tag>bandwidth</tag>
      <tag>outgoing</tag>
      <value minValue=\"0\">${BO}</value>
      <unit type=\"contextDependentUnits\" symbol=\"Mbps\">Megabits per second</unit>
    </data>
  </environment>
</eeml>
"

curl --silent --request PUT --header "X-PachubeApiKey: $APIKEY" --data "$XMLDATA" $URL > /dev/null