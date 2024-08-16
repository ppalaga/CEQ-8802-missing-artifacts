#!/bin/bash
set -x
set -e

LOCAL_REPO=~/zzz/test-repo
SETTINGS=~/orgs/cq-prod-3.8/reproducers/CEQ-8802-missing-artifacts/settings.xml

mkdir -p $LOCAL_REPO

# Remove all snapshots from local Maven repo unless it is empty
find $LOCAL_REPO -type d -name '*-SNAPSHOT' | xargs rm -Rf
find $LOCAL_REPO -type d -name '*redhat-*' | xargs rm -Rf

# path to unzipped local repos
#QUARKUS_MRRC_REPOSITORY=~/zzz/rh-quarkus-platform-3.8.5.SP1-maven-repository/maven-repository
QUARKUS_MRRC_REPOSITORY=~/zzz/rh-quarkus-platform-3.8.5.GA-maven-repository/maven-repository
CEQ_MRRC_REPOSITORY=$QUARKUS_MRRC_REPOSITORY
#~/zzz/rhaf-camel-4.4.0-for-quarkus-3.8.0.CR5-maven-repository/maven-repository
INDY_BASE_URL=https://indy.psi.redhat.com/api/content/maven/group/static

# get the versions from the MRRC repos
QUARKUS_BOM_GROUP_ID="com.redhat.quarkus.platform"
QUARKUS_BOM_ARTIFACT_ID="quarkus-bom"
CQ_BOM_GROUP_ID="com.redhat.quarkus.platform"
CQ_BOM_ARTIFACT_ID="quarkus-camel-bom"
QUARKUS_BOM_VERSION=$(ls $QUARKUS_MRRC_REPOSITORY/com/redhat/quarkus/platform/quarkus-bom-quarkus-platform-descriptor)
CQ_BOM_VERSION=$(ls $CEQ_MRRC_REPOSITORY/com/redhat/quarkus/platform/quarkus-camel-bom)
CAMEL_VERSION=$(ls $CEQ_MRRC_REPOSITORY/org/apache/camel/camel-direct)

# make sure you are on the right midstream branch
#git clone -b 3.8.0-product -o midstream https://github.com/jboss-fuse/camel-quarkus.git
#cd camel-quarkus

# Put the flattened BOM instead of the BOM with imports (some of which (such as jetty-bom) are missing in MRRC.zip)
cp poms/bom/src/main/generated/flattened-reduced-pom.xml poms/bom/pom.xml

# Install the missing quarkus-test-artemis arifact from Indy
QUARKUS_ARTEMIS_VERSION=$(ls $CEQ_MRRC_REPOSITORY/io/quarkiverse/artemis/quarkus-artemis-jms)
ARTEMIS_VERSION=$(ls $CEQ_MRRC_REPOSITORY/org/apache/activemq/artemis-commons)
# strip the redhat suffix
ARTEMIS_VERSION=$(echo $ARTEMIS_VERSION | sed 's|[-\\.]redhat-.*||')
if [ ! -f "$LOCAL_REPO/io/quarkiverse/artemis/quarkus-test-artemis/$QUARKUS_ARTEMIS_VERSION/quarkus-test-artemis-$QUARKUS_ARTEMIS_VERSION.jar" ]; then
    mkdir -p $LOCAL_REPO/io/quarkiverse/artemis/quarkus-test-artemis/$QUARKUS_ARTEMIS_VERSION
    curl $INDY_BASE_URL/io/quarkiverse/artemis/quarkus-test-artemis/$QUARKUS_ARTEMIS_VERSION/quarkus-test-artemis-$QUARKUS_ARTEMIS_VERSION.jar > $LOCAL_REPO/io/quarkiverse/artemis/quarkus-test-artemis/$QUARKUS_ARTEMIS_VERSION/quarkus-test-artemis-$QUARKUS_ARTEMIS_VERSION.jar
    curl $INDY_BASE_URL/io/quarkiverse/artemis/quarkus-test-artemis/$QUARKUS_ARTEMIS_VERSION/quarkus-test-artemis-$QUARKUS_ARTEMIS_VERSION.pom > $LOCAL_REPO/io/quarkiverse/artemis/quarkus-test-artemis/$QUARKUS_ARTEMIS_VERSION/quarkus-test-artemis-$QUARKUS_ARTEMIS_VERSION.pom
fi
# Replace quarkiverse-artemis.version in the top pom.xml
echo -e "cd /*[local-name() = 'project']//*[local-name() = 'properties']//*[local-name() = 'quarkiverse-artemis.version']\n cat text()\n set $QUARKUS_ARTEMIS_VERSION\n cat text()\n save\n bye" | xmllint --shell pom.xml
# Force some Artemis community versions in the test BOM
if grep -q "<artifactId>artemis-server</artifactId>" poms/bom-test/pom.xml; then
  echo "artemis-server already present in poms/bom-test/pom.xml."
else
  echo "Adding artemis-server constraint to poms/bom-test/pom.xml"
  sed -i "s|        </dependencies>|            <dependency>\n                <groupId>org.apache.activemq</groupId>\n                <artifactId>artemis-server</artifactId>\n                <version>${ARTEMIS_VERSION}</version>\n            </dependency>\n            <dependency>\n                <groupId>org.apache.activemq</groupId>\n                <artifactId>artemis-amqp-protocol</artifactId>\n                <version>${ARTEMIS_VERSION}</version>\n            </dependency>\n        </dependencies>|" poms/bom-test/pom.xml
fi

# Install the missing org.mapstruct:mapstruct-processor arifact from Indy
MAPSTRUCT_VERSION=$(ls $CEQ_MRRC_REPOSITORY/org/mapstruct/mapstruct)
if [ ! -f "$LOCAL_REPO/org/mapstruct/mapstruct-processor/$MAPSTRUCT_VERSION/mapstruct-processor-$MAPSTRUCT_VERSION.jar" ]; then
    mkdir -p $LOCAL_REPO/org/mapstruct/mapstruct-processor/$MAPSTRUCT_VERSION
    curl $INDY_BASE_URL/org/mapstruct/mapstruct-processor/$MAPSTRUCT_VERSION/mapstruct-processor-$MAPSTRUCT_VERSION.jar > $LOCAL_REPO/org/mapstruct/mapstruct-processor/$MAPSTRUCT_VERSION/mapstruct-processor-$MAPSTRUCT_VERSION.jar
    curl $INDY_BASE_URL/org/mapstruct/mapstruct-processor/$MAPSTRUCT_VERSION/mapstruct-processor-$MAPSTRUCT_VERSION.pom > $LOCAL_REPO/org/mapstruct/mapstruct-processor/$MAPSTRUCT_VERSION/mapstruct-processor-$MAPSTRUCT_VERSION.pom
fi

# get the Camel Quarkus version from the source tree
CQ_VERSION="$(xmllint --format --xpath "/*[local-name() = 'project']/*[local-name() = 'version']/text()" pom.xml)"

# Replace Camel version in the top pom.xml
echo -e "cd /*[local-name() = 'project']//*[local-name() = 'parent']//*[local-name() = 'version']\n cat text()\n set $CAMEL_VERSION\n cat text()\n save\n bye" | xmllint --shell pom.xml
echo -e "cd /*[local-name() = 'project']//*[local-name() = 'properties']//*[local-name() = 'camel.version']\n cat text()\n set $CAMEL_VERSION\n cat text()\n save\n bye" | xmllint --shell pom.xml

# Build some required artifacts
mvn clean install -N -Plocal-mrrc \
  -s $SETTINGS \
  -Dcq.prod-artifacts.skip \
  -DnoVirtualDependencies \
  -Dquarkus.platform.group-id=$QUARKUS_BOM_GROUP_ID \
  -Dquarkus.platform.artifact-id=$QUARKUS_BOM_ARTIFACT_ID \
  -Dquarkus.platform.version=$QUARKUS_BOM_VERSION \
  -Dcamel-quarkus.platform.group-id=$CQ_BOM_GROUP_ID \
  -Dcamel-quarkus.platform.artifact-id=camel-$CQ_BOM_ARTIFACT_ID \
  -Dcamel-quarkus.platform.version=$CQ_BOM_VERSION \
  -Dcamel-quarkus.version=$CQ_VERSION

mvn clean install -Plocal-mrrc -Dquickly \
  -s $SETTINGS \
  -f poms/pom.xml \
  -Dcq.prod-artifacts.skip \
  -DnoVirtualDependencies \
  -Dquarkus.platform.group-id=$QUARKUS_BOM_GROUP_ID \
  -Dquarkus.platform.artifact-id=$QUARKUS_BOM_ARTIFACT_ID \
  -Dquarkus.platform.version=$QUARKUS_BOM_VERSION \
  -Dcamel-quarkus.platform.group-id=$CQ_BOM_GROUP_ID \
  -Dcamel-quarkus.platform.artifact-id=$CQ_BOM_ARTIFACT_ID \
  -Dcamel-quarkus.platform.version=$CQ_BOM_VERSION \
  -Dcamel-quarkus.version=$CQ_VERSION

mvn clean install -Plocal-mrrc \
  -s $SETTINGS \
  -f integration-tests-support/pom.xml \
  -Dcq.prod-artifacts.skip \
  -DnoVirtualDependencies \
  -Dquarkus.platform.group-id=$QUARKUS_BOM_GROUP_ID \
  -Dquarkus.platform.artifact-id=$QUARKUS_BOM_ARTIFACT_ID \
  -Dquarkus.platform.version=$QUARKUS_BOM_VERSION \
  -Dcamel-quarkus.platform.group-id=$CQ_BOM_GROUP_ID \
  -Dcamel-quarkus.platform.artifact-id=$CQ_BOM_ARTIFACT_ID \
  -Dcamel-quarkus.platform.version=$CQ_BOM_VERSION \
  -Dcamel-quarkus.version=$CQ_VERSION

mvn clean install -Plocal-mrrc \
  -s $SETTINGS \
  -f integration-tests/messaging/pom.xml \
  -Dcq.prod-artifacts.skip \
  -DnoVirtualDependencies \
  -Dquarkus.platform.group-id=$QUARKUS_BOM_GROUP_ID \
  -Dquarkus.platform.artifact-id=$QUARKUS_BOM_ARTIFACT_ID \
  -Dquarkus.platform.version=$QUARKUS_BOM_VERSION \
  -Dcamel-quarkus.platform.group-id=$CQ_BOM_GROUP_ID \
  -Dcamel-quarkus.platform.artifact-id=$CQ_BOM_ARTIFACT_ID \
  -Dcamel-quarkus.platform.version=$CQ_BOM_VERSION \
  -Dcamel-quarkus.version=$CQ_VERSION

mvn clean install -Plocal-mrrc \
  -s $SETTINGS \
  -f integration-test-groups/http/common/pom.xml \
  -Dcq.prod-artifacts.skip \
  -DnoVirtualDependencies \
  -Dquarkus.platform.group-id=$QUARKUS_BOM_GROUP_ID \
  -Dquarkus.platform.artifact-id=$QUARKUS_BOM_ARTIFACT_ID \
  -Dquarkus.platform.version=$QUARKUS_BOM_VERSION \
  -Dcamel-quarkus.platform.group-id=$CQ_BOM_GROUP_ID \
  -Dcamel-quarkus.platform.artifact-id=$CQ_BOM_ARTIFACT_ID \
  -Dcamel-quarkus.platform.version=$CQ_BOM_VERSION \
  -Dcamel-quarkus.version=$CQ_VERSION

# Run the tests
# product/integration-tests-product/pom.xml
mvn clean test -Plocal-mrrc -fae \
  -s $SETTINGS \
  -f product/integration-tests-product/pom.xml \
  -DskipTests \
  -Dcq.prod-artifacts.skip \
  -DnoVirtualDependencies \
  -Dquarkus.platform.group-id=$QUARKUS_BOM_GROUP_ID \
  -Dquarkus.platform.artifact-id=$QUARKUS_BOM_ARTIFACT_ID \
  -Dquarkus.platform.version=$QUARKUS_BOM_VERSION \
  -Dcamel-quarkus.platform.group-id=$CQ_BOM_GROUP_ID \
  -Dcamel-quarkus.platform.artifact-id=$CQ_BOM_ARTIFACT_ID \
  -Dcamel-quarkus.platform.version=$CQ_BOM_VERSION \
  -Dcamel-quarkus.version=$CQ_VERSION

# Build the superapp
mvn clean test -Plocal-mrrc -fae \
  -s $SETTINGS \
  -f product/camel-quarkus-superapp/pom.xml \
  -DskipTests \
  -Dcq.prod-artifacts.skip \
  -DnoVirtualDependencies \
  -Dquarkus.platform.group-id=$QUARKUS_BOM_GROUP_ID \
  -Dquarkus.platform.artifact-id=$QUARKUS_BOM_ARTIFACT_ID \
  -Dquarkus.platform.version=$QUARKUS_BOM_VERSION \
  -Dcamel-quarkus.platform.group-id=$CQ_BOM_GROUP_ID \
  -Dcamel-quarkus.platform.artifact-id=$CQ_BOM_ARTIFACT_ID \
  -Dcamel-quarkus.platform.version=$CQ_BOM_VERSION \
  -Dcamel-quarkus.version=$CQ_VERSION
