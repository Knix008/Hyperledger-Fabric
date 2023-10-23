#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script brings up a Hyperledger Fabric network for testing smart contracts
# and applications. The test network consists of two organizations with one
# peer each, and a single node Raft ordering service. Users can also use this
# script to create a channel deploy a chaincode on the channel
#
# prepending $PWD/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
export PATH=${PWD}/../bin:$PATH
export FABRIC_CFG_PATH=${PWD}/configtx
export VERBOSE=true
export NETWORK=test

. scripts/utils.sh

# Obtain CONTAINER_IDS and remove them
# TODO Might want to make this optional - could clear other containers
# This function is called when you bring a network down
function clearContainers() {
  CONTAINER_IDS=$(docker ps -a | awk '($2 ~ /dev-peer.*/) {print $1}')
  if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
    infoln "No containers available for deletion"
  else
    docker rm -f $CONTAINER_IDS
  fi
}

# Delete any images that were generated as a part of this setup
# specifically the following images are often left behind:
# This function is called when you bring the network down
function removeUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*/) {print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    infoln "No images available for deletion"
  else
    docker rmi -f $DOCKER_IMAGE_IDS
  fi
}

# Versions of fabric known not to work with the test network
NONWORKING_VERSIONS="^1\.0\. ^1\.1\. ^1\.2\. ^1\.3\. ^1\.4\."

# Do some basic sanity checking to make sure that the appropriate versions of fabric
# binaries/images are available. In the future, additional checking for the presence
# of go or other items could be added.
function checkPrereqs() {
  ## Check if your have cloned the peer binaries and configuration files.
  peer version > /dev/null 2>&1

  if [[ $? -ne 0 || ! -d "../config" ]]; then
    errorln "Peer binary and configuration files not found.."
    errorln
    errorln "Follow the instructions in the Fabric docs to install the Fabric Binaries:"
    errorln "https://hyperledger-fabric.readthedocs.io/en/latest/install.html"
    exit 1
  fi
  # use the fabric tools container to see if the samples and binaries match your
  # docker images
  LOCAL_VERSION=$(peer version | sed -ne 's/ Version: //p')
  DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-tools:$IMAGETAG peer version | sed -ne 's/ Version: //p' | head -1)

  infoln "LOCAL_VERSION=$LOCAL_VERSION"
  infoln "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

  if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
    warnln "Local fabric binaries and docker images are out of  sync. This may cause problems."
  fi

  for UNSUPPORTED_VERSION in $NONWORKING_VERSIONS; do
    infoln "$LOCAL_VERSION" | grep -q $UNSUPPORTED_VERSION
    if [ $? -eq 0 ]; then
      fatalln "Local Fabric binary version of $LOCAL_VERSION does not match the versions supported by the test network."
    fi

    infoln "$DOCKER_IMAGE_VERSION" | grep -q $UNSUPPORTED_VERSION
    if [ $? -eq 0 ]; then
      fatalln "Fabric Docker image version of $DOCKER_IMAGE_VERSION does not match the versions supported by the test network."
    fi
  done

  ## Check for fabric-ca
  if [ "$CRYPTO" == "Certificate Authorities" ]; then

    fabric-ca-client version > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      errorln "fabric-ca-client binary not found.."
      errorln
      errorln "Follow the instructions in the Fabric docs to install the Fabric Binaries:"
      errorln "https://hyperledger-fabric.readthedocs.io/en/latest/install.html"
      exit 1
    fi
    CA_LOCAL_VERSION=$(fabric-ca-client version | sed -ne 's/ Version: //p')
    CA_DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-ca:$CA_IMAGETAG fabric-ca-client version | sed -ne 's/ Version: //p' | head -1)
    infoln "CA_LOCAL_VERSION=$CA_LOCAL_VERSION"
    infoln "CA_DOCKER_IMAGE_VERSION=$CA_DOCKER_IMAGE_VERSION"

    if [ "$CA_LOCAL_VERSION" != "$CA_DOCKER_IMAGE_VERSION" ]; then
      warnln "Local fabric-ca binaries and docker images are out of sync. This may cause problems."
    fi
  fi
}

# Before you can bring up a network, each organization needs to generate the crypto
# material that will define that organization on the network. Because Hyperledger
# Fabric is a permissioned blockchain, each node and user on the network needs to
# use certificates and keys to sign and verify its actions. In addition, each user
# needs to belong to an organization that is recognized as a member of the network.
# You can use the Cryptogen tool or Fabric CAs to generate the organization crypto
# material.

# By default, the sample network uses cryptogen. Cryptogen is a tool that is
# meant for development and testing that can quickly create the certificates and keys
# that can be consumed by a Fabric network. The cryptogen tool consumes a series
# of configuration files for each organization in the "organizations/cryptogen"
# directory. Cryptogen uses the files to generate the crypto  material for each
# org in the "organizations" directory.

# You can also Fabric CAs to generate the crypto material. CAs sign the certificates
# and keys that they generate to create a valid root of trust for each organization.
# The script uses Docker Compose to bring up three CAs, one for each peer organization
# and the ordering organization. The configuration file for creating the Fabric CA
# servers are in the "organizations/fabric-ca" directory. Within the same directory,
# the "registerEnroll.sh" script uses the Fabric CA client to create the identities,
# certificates, and MSP folders that are needed to create the test network in the
# "organizations/ordererOrganizations" directory.

# Create Organization crypto material using cryptogen or CAs
function createOrgs() {
  if [ -d "organizations/peerOrganizations" ]; then
    rm -Rf organizations/peerOrganizations && rm -Rf organizations/ordererOrganizations
  fi

  # Create crypto material using cryptogen
  if [ "$CRYPTO" == "cryptogen" ]; then
    which cryptogen
    if [ "$?" -ne 0 ]; then
      fatalln "cryptogen tool not found. exiting"
    fi
    infoln "Generating certificates using cryptogen tool"

    infoln "Creating Org1 Identities"

    set -x
    cryptogen generate --config=./organizations/cryptogen/crypto-config-org1.yaml --output="organizations"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
      fatalln "Failed to generate certificates..."
    fi

    infoln "Creating Org2 Identities"

    set -x
    cryptogen generate --config=./organizations/cryptogen/crypto-config-org2.yaml --output="organizations"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
      fatalln "Failed to generate certificates..."
    fi

    infoln "Creating Org3 Identities"

    set -x
    cryptogen generate --config=./organizations/cryptogen/crypto-config-org3.yaml --output="organizations"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
      fatalln "Failed to generate certificates..."
    fi

    infoln "Creating Orderer Org Identities"

    set -x
    cryptogen generate --config=./organizations/cryptogen/crypto-config-orderer.yaml --output="organizations"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
      fatalln "Failed to generate certificates..."
    fi
  fi

  # Create crypto material using Fabric CA
  if [ "$CRYPTO" == "Certificate Authorities" ]; then
    infoln "Generating certificates using Fabric CA"

    docker stack deploy -c $COMPOSE_FILE_CA fabric-ca
    sleep 3
    . organizations/fabric-ca/registerEnroll.sh

    # We need to check tls certification before we go further.
    while :
      do
        if [ ! -f "organizations/fabric-ca/org1/tls-cert.pem" ]; then
          sleep 1
        else
          break
        fi
      done
    
    while :
      do
        if [ ! -f "organizations/fabric-ca/org2/tls-cert.pem" ]; then
          sleep 1
        else
          break
        fi
      done
    
    while :
      do
        if [ ! -f "organizations/fabric-ca/org3/tls-cert.pem" ]; then
          sleep 1
        else
          break
        fi
      done
    
    while :
      do
        if [ ! -f "organizations/fabric-ca/ordererOrg/tls-cert.pem" ]; then
          sleep 1
        else
          break
        fi
      done

    infoln "Creating Org1 Identities"
    createOrg1
    infoln "Creating Org2 Identities"
    createOrg2
    infoln "Creating Org3 Identities"
    createOrg3
    infoln "Creating Orderer Org Identities"
    createOrderer

  fi

  infoln "Generating CCP files for Org1,Org2, and Org3"
  ./organizations/ccp-generate.sh
}

# Once you create the organization crypto material, you need to create the
# genesis block of the orderer system channel. This block is required to bring
# up any orderer nodes and create any application channels.

# The configtxgen tool is used to create the genesis block. Configtxgen consumes a
# "configtx.yaml" file that contains the definitions for the sample network. The
# genesis block is defined using the "TwoOrgsOrdererGenesis" profile at the bottom
# of the file. This profile defines a sample consortium, "SampleConsortium",
# consisting of our two Peer Orgs. This consortium defines which organizations are
# recognized as members of the network. The peer and ordering organizations are defined
# in the "Profiles" section at the top of the file. As part of each organization
# profile, the file points to a the location of the MSP directory for each member.
# This MSP is used to create the channel MSP that defines the root of trust for
# each organization. In essence, the channel MSP allows the nodes and users to be
# recognized as network members. The file also specifies the anchor peers for each
# peer org. In future steps, this same file is used to create the channel creation
# transaction and the anchor peer updates.
#
#
# If you receive the following warning, it can be safely ignored:
#
# [bccsp] GetDefault -> WARN 001 Before using BCCSP, please call InitFactories(). Falling back to bootBCCSP.
#
# You can ignore the logs regarding intermediate certs, we are not using them in
# this crypto implementation.

# Generate orderer system channel genesis block.
function createConsortium() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    fatalln "configtxgen tool not found."
  fi

  infoln "Generating Orderer Genesis block"

  # Note: For some unknown reason (at least for now) the block file can't be
  # named orderer.genesis.block or the orderer will fail to launch!
  set -x
  configtxgen -profile OrdererGenesis -channelID system-channel -outputBlock ./system-genesis-block/genesis.block
  res=$?
  { set +x; } 2>/dev/null
  if [ $res -ne 0 ]; then
    fatalln "Failed to generate orderer genesis block..."
  fi
}

# After we create the org crypto material and the system channel genesis block,
# we can now bring up the peers and ordering service. By default, the base
# file for creating the network is "docker-compose-test-net.yaml" in the ``docker``
# folder. This file defines the environment variables and file mounts that
# point the crypto material and genesis block that were created in earlier.

# Bring up the peer and orderer nodes using docker compose.
function networkUp() {
  # Create network 
  infoln "Creating docker overlay network..."
  docker network create --driver overlay --attachable $NETWORK > /dev/null 2>&1
  sleep 3

  checkPrereqs
  # generate artifacts if they don't exist
  if [ ! -d "organizations/peerOrganizations" ]; then
    createOrgs
    createConsortium
  fi
 
  # deploy peer and orderer nodes
  docker stack deploy -c $COMPOSE_FILE_PEER fabric-peer
  docker stack deploy -c $COMPOSE_FILE_ORDERER fabric-orderer
  docker stack deploy -c $COMPOSE_FILE_CLI fabric-cli
  sleep 3

  # if couchdb selected, deploy it.
  if [ "${DATABASE}" == "couchdb" ]; then
    # COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_COUCH}"
    docker stack deploy -c $COMPOSE_FILE_COUCH fabric-couchdb
    sleep 3
  fi

  # copy peer0.org1.example.com User1 private key to caliper
  infoln "Copying private key for caliper benchmarks..."
  cp ${PWD}/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore/*_sk ../caliper-benchmarks/keys/priv_sk

  # copy connection profiles into node.js and golang REST API server.
  infoln "Copying connection profiles..."
  cp ${PWD}/organizations/peerOrganizations/org1.example.com/connection-org1.json ../server/connection
  cp ${PWD}/organizations/peerOrganizations/org2.example.com/connection-org2.json ../server/connection
  cp ${PWD}/organizations/peerOrganizations/org3.example.com/connection-org3.json ../server/connection
  cp ${PWD}/organizations/peerOrganizations/org1.example.com/connection-org1.yaml ../server/connection
  cp ${PWD}/organizations/peerOrganizations/org2.example.com/connection-org2.yaml ../server/connection
  cp ${PWD}/organizations/peerOrganizations/org3.example.com/connection-org3.yaml ../server/connection

  # check running containers left.
  infoln "Displying working node information..."
  docker ps -a
  if [ $? -ne 0 ]; then
    fatalln "Unable to start network"
  fi
}

# call the script to create the channel, join the peers of org1 and org2,
# and then update the anchor peers for each organization
function createChannel() {
  # Bring up the network if it is not already up.
  if [ ! -d "organizations/peerOrganizations" ]; then
    infoln "Bringing up network"
    networkUp
  fi
  # Give some time to bring up the fabric newtork.
  sleep 5
  # now run the script that creates a channel. This script uses configtxgen once
  # more to create the channel creation transaction and the anchor peer updates.
  # configtx.yaml is mounted in the cli container, which allows us to use it to
  # create the channel artifacts
  scripts/createChannel.sh $CHANNEL_NAME $CLI_DELAY $MAX_RETRY $VERBOSE
}

## Call the script to deploy a chaincode to the channel
function deployCC() {
  scripts/deployCC.sh $CHANNEL_NAME $CC_NAME $CC_SRC_PATH $CC_SRC_LANGUAGE $CC_VERSION $CC_SEQUENCE $CC_INIT_FCN $CC_END_POLICY $CC_COLL_CONFIG $CLI_DELAY $MAX_RETRY $VERBOSE

  if [ $? -ne 0 ]; then
    fatalln "Deploying chaincode failed"
  fi
}

## Run the hyperledger fabric explorer
function explorerUp() {
  infoln "Running Hyperledger Fabric Explorer"
  pushd ../explorer > /dev/null 2>&1
  cp ./base/test-network.json ./connection-profile
  PRIV_KEY=$(ls ../network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore/ | grep _sk)
  sed -i "s/Org1_Admin_PrivateKey/${PRIV_KEY}/g" ./connection-profile/test-network.json
  docker stack deploy -c docker-compose-explorer.yaml fabric-explorer
  popd > /dev/null 2>&1
  docker ps -a
}

## Stop the hyperledger fabric explorer
function explorerDown() {
  infoln "Remove explorer and explorerdb containers and volumes..."
  # Remove explorer and explorerdb containers.
  EXPLORER_CONTAINER_IDS=$(docker ps -a | awk '($2 ~ /hyperledger\/explorer.*/) {print $1}')
  if [ -z "$EXPLORER_CONTAINER_IDS" -o "$EXPLORER_CONTAINER_IDS" == " " ]; then
    infoln "No containers available for explorer and explorerdb"
  else
    infoln "Deleting explorer and exploerdb containers."
    docker stack rm fabric-explorer > /dev/null 2>&1
    sleep 3
    pushd ../explorer > /dev/null 2>&1
    rm -rf connection-profile/test-network.json > /dev/null 2>&1
    popd > /dev/null 2>&1
  fi
  # remove all data for explorer
  docker run --rm -v $(pwd)/../explorer:/data busybox sh -c 'cd /data && rm -rf pgdata/* wallet/*' > /dev/null 2>&1
  sleep 3
  infoln "Remove done."
  docker ps -a
}

# Tear down running network
function networkDown() {
  #docker stack rm fabric-peer fabric-couchdb fabric-ca
  docker stack rm fabric-peer > /dev/null 2>&1
  docker stack rm fabric-orderer > /dev/null 2>&1
  docker stack rm fabric-cli > /dev/null 2>&1
  docker stack rm fabric-ca > /dev/null 2>&1
  sleep 3 

  # if couchdb selected, deploy it.
  if [ "${DATABASE}" == "couchdb" ]; then
    infoln "Removing couchdb service..."
    docker stack rm fabric-couchdb > /dev/null 2>&1
    sleep 3
  fi
  
  #docker rm -f explorer.mynetwork.com explorerdb.mynetwork.com
  #pushd ../explorer
  #rm -rf connection-profile/test-network.json
  #popd
  
  # docker-compose -f $COMPOSE_FILE_COUCH_ORG3 -f $COMPOSE_FILE_ORG3 down --volumes --remove-orphans
  # Don't remove the generated artifacts -- note, the ledgers are always removed
  if [ "$MODE" != "restart" ]; then
    # Bring down the network, deleting the volumes
    #Cleanup the chaincode containers
    clearContainers
    #Cleanup images
    removeUnwantedImages
    # remove orderer block and other channel configuration transactions and certs
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf system-genesis-block/*.block organizations/peerOrganizations organizations/ordererOrganizations'
    ## remove fabric ca artifacts
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org1/msp organizations/fabric-ca/org1/tls-cert.pem organizations/fabric-ca/org1/ca-cert.pem organizations/fabric-ca/org1/IssuerPublicKey organizations/fabric-ca/org1/IssuerRevocationPublicKey organizations/fabric-ca/org1/fabric-ca-server.db'
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org2/msp organizations/fabric-ca/org2/tls-cert.pem organizations/fabric-ca/org2/ca-cert.pem organizations/fabric-ca/org2/IssuerPublicKey organizations/fabric-ca/org2/IssuerRevocationPublicKey organizations/fabric-ca/org2/fabric-ca-server.db'
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org3/msp organizations/fabric-ca/org3/tls-cert.pem organizations/fabric-ca/org3/ca-cert.pem organizations/fabric-ca/org3/IssuerPublicKey organizations/fabric-ca/org3/IssuerRevocationPublicKey organizations/fabric-ca/org3/fabric-ca-server.db'
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/ordererOrg/msp organizations/fabric-ca/ordererOrg/tls-cert.pem organizations/fabric-ca/ordererOrg/ca-cert.pem organizations/fabric-ca/ordererOrg/IssuerPublicKey organizations/fabric-ca/ordererOrg/IssuerRevocationPublicKey organizations/fabric-ca/ordererOrg/fabric-ca-server.db'
    # remove channel and script artifacts
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf channel-artifacts log.txt *.tar.gz'

    # remove all volumes mounted for peers and oreders
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf production/orderer0/* production/orderer1/* production/peer0org1/* production/peer0org2/* production/peer0org3/*'
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf production/couchdb/data0/* production/couchdb/data0/.delete production/couchdb/data1/* production/couchdb/data1/.delete production/couchdb/data2/* production/couchdb/data2/.delete'
    # remove connection profiles in node.js server
    infoln "Removing all wallets."
    rm ../server/connection/*.json > /dev/null 2>&1
    rm ../server/connection/*.yaml > /dev/null 2>&1
    rm ../server/wallets/wallet1/*.id > /dev/null 2>&1
    
    # remove network
    infoln "Removing docker network interface."
    docker network rm $NETWORK > /dev/null 2>&1
    sleep 3

    # remove any left data in docker volume.
    infoln "Removing docker volumes."
    docker volume prune --force > /dev/null 2>&1
    sleep 5

    # check any docker containers left.
    infoln "Any left containers?"
    docker ps -a
  fi
}

# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform, e.g., darwin-amd64 or linux-amd64
OS_ARCH=$(echo "$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
# Using crpto vs CA. default is cryptogen
CRYPTO="cryptogen"
# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
MAX_RETRY=5
# default for delay between commands
CLI_DELAY=3
# channel name defaults to "mychannel"
CHANNEL_NAME="mychannel"
# chaincode name defaults to "NA"         
CC_NAME="NA"
# chaincode path defaults to "NA"
CC_SRC_PATH="NA"
# endorsement policy defaults to "NA". This would allow chaincodes to use the majority default policy.
CC_END_POLICY="NA"
# collection configuration defaults to "NA"
CC_COLL_CONFIG="NA"
# chaincode init function defaults to "NA"
CC_INIT_FCN="NA"
# use this as the default docker-compose yaml peer definition
COMPOSE_FILE_PEER=docker/docker-compose-peer.yaml
# use this as the default docker-compose yaml order definition
COMPOSE_FILE_ORDERER=docker/docker-compose-orderer.yaml
# use this as the default docker-ccompose yaml cli definition
COMPOSE_FILE_CLI=docker/docker-compose-cli.yaml
# docker-compose.yaml file if you are using couchdb
COMPOSE_FILE_COUCH=docker/docker-compose-couch.yaml
# certificate authorities compose file
COMPOSE_FILE_CA=docker/docker-compose-ca.yaml
# use this as the docker compose couch file for org3
# COMPOSE_FILE_COUCH_ORG3=addOrg3/docker/docker-compose-couch-org3.yaml
# use this as the default docker-compose yaml definition for org3
# COMPOSE_FILE_ORG3=addOrg3/docker/docker-compose-org3.yaml
#
# chaincode language defaults to "NA"
CC_SRC_LANGUAGE="NA"
# Chaincode version
CC_VERSION="1.0"
# Chaincode definition sequence
CC_SEQUENCE=1
# default image tag
IMAGETAG="2.4.0"
# default ca image tag
CA_IMAGETAG="1.4.9"
# default database
DATABASE="leveldb"
#DATABASE="couchdb"

# Parse commandline args

## Parse mode
if [[ $# -lt 1 ]] ; then
  printHelp
  exit 0
else
  MODE=$1
  shift
fi

# parse a createChannel subcommand if used
if [[ $# -ge 1 ]] ; then
  key="$1"
  if [[ "$key" == "createChannel" ]]; then
      export MODE="createChannel"
      shift
  fi
fi

# parse flags
while [[ $# -ge 1 ]] ; do
  key="$1"
  case $key in
  -h )
    printHelp $MODE
    exit 0
    ;;
  -c )
    CHANNEL_NAME="$2"
    shift
    ;;
  -ca )
    CRYPTO="Certificate Authorities"
    ;;
  -r )
    MAX_RETRY="$2"
    shift
    ;;
  -d )
    CLI_DELAY="$2"
    shift
    ;;
  -s )
    DATABASE="$2"
    shift
    ;;
  -ccl )
    CC_SRC_LANGUAGE="$2"
    shift
    ;;
  -ccn )
    CC_NAME="$2"
    shift
    ;;
  -ccv )
    CC_VERSION="$2"
    shift
    ;;
  -ccs )
    CC_SEQUENCE="$2"
    shift
    ;;
  -ccp )
    CC_SRC_PATH="$2"
    shift
    ;;
  -ccep )
    CC_END_POLICY="$2"
    shift
    ;;
  -cccg )
    CC_COLL_CONFIG="$2"
    shift
    ;;
  -cci )
    CC_INIT_FCN="$2"
    shift
    ;;
  -i )
    IMAGETAG="$2"
    shift
    ;;
  -cai )
    CA_IMAGETAG="$2"
    shift
    ;;
  -verbose )
    VERBOSE=true
    shift
    ;;
  * )
    errorln "Unknown flag: $key"
    printHelp
    exit 1
    ;;
  esac
  shift
done

# Are we generating crypto material with this command?
if [ ! -d "organizations/peerOrganizations" ]; then
  CRYPTO_MODE="with crypto from '${CRYPTO}'"
else
  CRYPTO_MODE=""
fi

# Determine mode of operation and printing out what we asked for
if [ "$MODE" == "up" ]; then
  infoln "Starting nodes with CLI timeout of '${MAX_RETRY}' tries and CLI delay of '${CLI_DELAY}' seconds and using database '${DATABASE}' ${CRYPTO_MODE}"
elif [ "$MODE" == "createChannel" ]; then
  infoln "Creating channel '${CHANNEL_NAME}'."
  infoln "If network is not up, starting nodes with CLI timeout of '${MAX_RETRY}' tries and CLI delay of '${CLI_DELAY}' seconds and using database '${DATABASE} ${CRYPTO_MODE}"
elif [ "$MODE" == "down" ]; then
  infoln "Stopping network"
elif [ "$MODE" == "restart" ]; then
  infoln "Restarting network"
elif [ "$MODE" == "deployCC" ]; then
  infoln "deploying chaincode on channel '${CHANNEL_NAME}'"
elif [ "$MODE" == "explorerUp" ]; then
  infoln "Run hyperledger fabric explorer"
elif [ "$MODE" == "explorerDown" ]; then
  infoln "Stop hyperledger fabric explorer"
else
  printHelp
  exit 1
fi

if [ "${MODE}" == "up" ]; then
  networkUp
elif [ "${MODE}" == "createChannel" ]; then
  createChannel
elif [ "${MODE}" == "deployCC" ]; then
  deployCC
elif [ "${MODE}" == "explorerUp" ]; then
  explorerUp
elif [ "${MODE}" == "explorerDown" ]; then
  explorerDown
elif [ "${MODE}" == "down" ]; then
  networkDown
else
  printHelp
  exit 1
fi
