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
MRRC_URL="https://download.hosts.prod.upshift.rdu2.redhat.com/rcm-guest/staging/rhaf/scratch/quarkus-platform-3.8.6.DR4/rh-quarkus-platform-3.8.6.DR4-maven-repository.zip"
MRRC_ZIP_PATH="$SCRIPT_DIR/mrrc/$(basename "$MRRC_URL")"
if [ ! -f "$MRRC_ZIP_PATH" ]; then
    curl "$MRRC_URL" > "$MRRC_ZIP_PATH"
fi

ROOT_ZIP_DIR="$(unzip -l "$MRRC_ZIP_PATH" | awk '/\/$/{print $4; exit}')"
ROOT_ZIP_DIR="${ROOT_ZIP_DIR%%/*}"

MRRC_EXPANDED_PATH="${MRRC_ZIP_PATH%.*}"
if [ ! -d "$MRRC_EXPANDED_PATH" ]; then
    MRRC_EXPANDED_TEMP_PATH="$SCRIPT_DIR/mrrc/temp"
    rm -rf "$MRRC_EXPANDED_TEMP_PATH"
    unzip -qq "$MRRC_ZIP_PATH" -d "$MRRC_EXPANDED_TEMP_PATH"
    mkdir -p "$MRRC_EXPANDED_PATH"
    mv -t "$MRRC_EXPANDED_PATH" "$MRRC_EXPANDED_TEMP_PATH/$ROOT_ZIP_DIR/"*
    rm -rf "$MRRC_EXPANDED_TEMP_PATH"
fi

# path to unzipped local repos
QUARKUS_MRRC_REPOSITORY="$MRRC_EXPANDED_PATH/maven-repository"
# For Platfrom builds there is only one MRRC.zip
CEQ_MRRC_REPOSITORY=$QUARKUS_MRRC_REPOSITORY

sed "s|QUARKUS_MRRC_REPOSITORY|$QUARKUS_MRRC_REPOSITORY|g" "$SETTINGS_TEMPLATE" | sed "s|LOCAL_REPO|$LOCAL_REPO|g" > "$SETTINGS"

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

INDY_BASE_URL=https://indy.psi.redhat.com/api/content/maven/group/static
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

indy io.quarkiverse.artemis quarkus-test-artemis $QUARKUS_ARTEMIS_VERSION "pom jar"
indy org.apache.activemq artemis-server $ARTEMIS_VERSION "pom jar"
indy org.apache.activemq artemis-amqp-protocol $ARTEMIS_VERSION "pom jar"
indy org.apache.activemq artemis-protocols $ARTEMIS_VERSION "pom jar"

indy org.apache.activemq artemis-journal $ARTEMIS_VERSION "pom jar"
indy org.apache.activemq artemis-jdbc-store $ARTEMIS_VERSION "pom jar"
indy org.apache.activemq artemis-quorum-api $ARTEMIS_VERSION "pom jar"
indy org.apache.activemq activemq-artemis-native 2.0.0.redhat-00005 "pom jar"

indy org.jctools jctools-parent 2.1.2.redhat-00003 "pom"
indy org.jctools jctools-core 2.1.2.redhat-00003 "pom jar"
indy org.apache.commons commons-configuration2 2.8.0.redhat-00002 "pom jar"
indy org.apache.commons commons-dbcp2 2.7.0.redhat-00001 "pom jar"
indy org.apache.commons commons-parent 48.0.0.redhat-00001 "pom"
indy org.apache apache 21.0.0.redhat-00001 "pom"
indy org.apache apache 23.0.0.redhat-00011 "pom"

# Manage quarkus-test-artemis manually, while it is not managed by the platform BOM
if ! grep -q "<version>$QUARKUS_ARTEMIS_VERSION</version>" integration-tests/jms-artemis-client/pom.xml ; then
    sed -i "s|^    <dependencies>|\n    <dependencyManagement>\n        <dependencies>\n            <dependency>\n                <groupId>io.quarkiverse.artemis</groupId>\n                <artifactId>quarkus-test-artemis</artifactId>\n                <version>$QUARKUS_ARTEMIS_VERSION</version>\n            </dependency>\n        </dependencies>\n    </dependencyManagement>\n\n    <dependencies>|" integration-tests/jms-artemis-client/pom.xml
fi

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


# This should not be necessary after 3.8.5.DR5
if ! grep -q "<artifactId>listenablefuture</artifactId>" product/superapp/pom.xml ; then
    sed -i "s|<artifactId>camel-quarkus-kudu</artifactId>|<artifactId>camel-quarkus-kudu</artifactId>\n            <exclusions>\n                <exclusion>\n                    <groupId>com.google.guava</groupId>\n                    <artifactId>listenablefuture</artifactId>\n                </exclusion>\n            </exclusions>|" product/superapp/pom.xml
fi

# Install SAP artifacts
SAP_INTERNAL_BASE="https://nexus.fuse-qe.eng.rdu2.redhat.com/repository/sap-internal"
SAP_LIB_DIR="integration-tests-jvm/sap/lib"
mkdir -p "$SAP_LIB_DIR"
curl $SAP_INTERNAL_BASE/com/sap/conn/idoc/sapidoc3/3.1.1/sapidoc3-3.1.1.jar > $SAP_LIB_DIR/sapidoc3.jar
curl $SAP_INTERNAL_BASE/com/sap/conn/jco/sapjco3/3.1.4/sapjco3-3.1.4.jar > $SAP_LIB_DIR/sapjco3.jar

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
  -DskipTests \
  -Pmixed \
  -f product/pom.xml \
  -Dcq.prod-artifacts.skip \
  -DnoVirtualDependencies \
  -Dquarkus.platform.group-id=$QUARKUS_BOM_GROUP_ID \
  -Dquarkus.platform.artifact-id=$QUARKUS_BOM_ARTIFACT_ID \
  -Dquarkus.platform.version=$QUARKUS_BOM_VERSION \
  -Dcamel-quarkus.platform.group-id=$CQ_BOM_GROUP_ID \
  -Dcamel-quarkus.platform.artifact-id=$CQ_BOM_ARTIFACT_ID \
  -Dcamel-quarkus.platform.version=$CQ_BOM_VERSION \
  -Dcamel-quarkus.version=$CQ_VERSION
