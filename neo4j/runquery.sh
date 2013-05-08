#!/bin/bash

URL="http://lenny.cs.indiana.edu:7475/db/data/cypher"

ID="$@"
ID=$(echo $ID | sed -e 's/ /,/g')
CYPHERQUERY="START m = node($ID) MATCH n-[r]->m WITH m, count(r) as cnt SET m.indegree = cnt WITH m MATCH n-[r]->m SET r.indegweight = (1.0/m.indegree);"

POSTQUERY=$(cat <<EOF
{
"query" : "$CYPHERQUERY"
}
EOF
)

curl -X POST $URL -d "$POSTQUERY" \
    -H "Accept: application/json"\
    -H "Content-Type: application/json"