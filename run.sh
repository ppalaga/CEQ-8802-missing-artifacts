#!/bin/bash
set -x
set -e

# A script to reproduce https://issues.redhat.com/browse/CEQ-9743
# Run this from the root repository of Camel Quarkus, the https://github.com/jboss-fuse/camel-quarkus 3.8.0-product branch

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
SETTINGS_TEMPLATE="$SCRIPT_DIR/settings-template.xml"
SETTINGS="$SCRIPT_DIR/mrrc/settings.xml"

LOCAL_REPO="$SCRIPT_DIR/local-repo"
mkdir -p "$LOCAL_REPO"

# Remove all snapshots and -redhat versions from local Maven repo
find $LOCAL_REPO -type d -name '*-SNAPSHOT' | xargs rm -Rf
find $LOCAL_REPO -type d -name '*redhat-*' | xargs rm -Rf

# Download expand mrrc
MRRC_ZIP_PATH="$SCRIPT_DIR/mrrc/rh-quarkus-platform-3.8.5.SP1-maven-repository.zip"
if [ ! -f "$MRRC_ZIP_PATH" ]; then
    curl https://download.eng.bos.redhat.com/rcm-guest/staging/quarkus/quarkus-platform-3.8.5.SP1.CR1/rh-quarkus-platform-3.8.5.SP1.CR1-maven-repository.zip > "$MRRC_ZIP_PATH"
fi
MRRC_EXPANDED_PATH="${MRRC_ZIP_PATH%.*}"
if [ ! -d "$MRRC_EXPANDED_PATH" ]; then
    unzip "$MRRC_ZIP_PATH" -d "$(dirname "$MRRC_EXPANDED_PATH")"
fi

# path to unzipped local repos
QUARKUS_MRRC_REPOSITORY="$MRRC_EXPANDED_PATH/maven-repository"
# For Platfrom builds there is only one MRRC.zip
CEQ_MRRC_REPOSITORY=$QUARKUS_MRRC_REPOSITORY
INDY_BASE_URL=https://indy.psi.redhat.com/api/content/maven/group/static

sed "s|QUARKUS_MRRC_REPOSITORY|$QUARKUS_MRRC_REPOSITORY|g" "$SETTINGS_TEMPLATE" \
  | sed "s|INDY_URL|$INDY_BASE_URL|g" \
  | sed "s|LOCAL_REPO|$LOCAL_REPO|g" > "$SETTINGS"

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

# Workaround the the missing Jetty BOM
cp poms/bom/src/main/generated/flattened-reduced-pom.xml poms/bom/pom.xml

indy () {
    local groupPath="$(echo "$1" | sed 's|\.|/|g')"
    local artifactId="$2"
    local version="$3"
    local types="$4"
    mkdir -p $LOCAL_REPO/$groupPath/$artifactId/$version
    #export IFS=' '
    for type in $types; do
        echo "type =${type}="
        curl --insecure $INDY_BASE_URL/$groupPath/$artifactId/$version/$artifactId-$version.$type > $LOCAL_REPO/$groupPath/$artifactId/$version/$artifactId-$version.$type
    done
}


# Install the missing quarkus-test-artemis arifact from Indy
QUARKUS_ARTEMIS_VERSION=$(ls $CEQ_MRRC_REPOSITORY/io/quarkiverse/artemis/quarkus-artemis-jms)
ARTEMIS_VERSION=$(ls $CEQ_MRRC_REPOSITORY/org/apache/activemq/artemis-commons)
# Replace quarkiverse-artemis.version in the top pom.xml
echo -e "cd /*[local-name() = 'project']//*[local-name() = 'properties']//*[local-name() = 'quarkiverse-artemis.version']\n cat text()\n set $QUARKUS_ARTEMIS_VERSION\n cat text()\n save\n bye" | xmllint --shell pom.xml

# Force some Artemis community versions in the test BOM
#if grep -q "<artifactId>artemis-server</artifactId>" poms/bom-test/pom.xml; then
#  echo "artemis-server already present in poms/bom-test/pom.xml."
#else
#  echo "Adding artemis-server constraint to poms/bom-test/pom.xml"
#  sed -i "s|        </dependencies>|            <dependency>\n                <groupId>org.apache.activemq</groupId>\n                <artifactId>artemis-server</artifactId>\n                <version>${ARTEMIS_VERSION}</version>\n            </dependency>\n            <dependency>\n                <groupId>org.apache.activemq</groupId>\n                <artifactId>artemis-amqp-protocol</artifactId>\n                <version>${ARTEMIS_VERSION}</version>\n            </dependency>\n        </dependencies>|" poms/bom-test/pom.xml
#fi

# Install mapstruct-processor from Indy
MAPSTRUCT_VERSION=$(ls $CEQ_MRRC_REPOSITORY/org/mapstruct/mapstruct)
mkdir -p $LOCAL_REPO/org/mapstruct/mapstruct-processor/$MAPSTRUCT_VERSION
curl --insecure $INDY_BASE_URL/org/mapstruct/mapstruct-processor/$MAPSTRUCT_VERSION/mapstruct-processor-$MAPSTRUCT_VERSION.jar > $LOCAL_REPO/org/mapstruct/mapstruct-processor/$MAPSTRUCT_VERSION/mapstruct-processor-$MAPSTRUCT_VERSION.jar
curl --insecure $INDY_BASE_URL/org/mapstruct/mapstruct-processor/$MAPSTRUCT_VERSION/mapstruct-processor-$MAPSTRUCT_VERSION.pom > $LOCAL_REPO/org/mapstruct/mapstruct-processor/$MAPSTRUCT_VERSION/mapstruct-processor-$MAPSTRUCT_VERSION.pom

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
#

mvn clean test -Plocal-mrrc -fae \
  -s $SETTINGS \
  -Pindy \
  -f integration-tests/jms-artemis-client/pom.xml \
  -Denforcer.skip \
  -Dcq.prod-artifacts.skip \
  -DnoVirtualDependencies \
  -Dquarkus.platform.group-id=$QUARKUS_BOM_GROUP_ID \
  -Dquarkus.platform.artifact-id=$QUARKUS_BOM_ARTIFACT_ID \
  -Dquarkus.platform.version=$QUARKUS_BOM_VERSION \
  -Dcamel-quarkus.platform.group-id=$CQ_BOM_GROUP_ID \
  -Dcamel-quarkus.platform.artifact-id=$CQ_BOM_ARTIFACT_ID \
  -Dcamel-quarkus.platform.version=$CQ_BOM_VERSION \
  -Dcamel-quarkus.version=$CQ_VERSION
