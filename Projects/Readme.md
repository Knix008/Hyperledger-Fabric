This directory will have all files need to build Hyperledger Fabric 2.2.0 network.
Please, do the following steps.

1. Make directory exported for NFS(Network File System).
   YOu can do it in the "/etc/exports" file like the following line.
   "/home/shkwon/Project/hyperledger_fabric *(rw,sync,no_root_squash,no_subtree_check)"
2. To mount the exported directory from the other node, you need to run the following command,
   "mount the-host-ip-address:/home/shkwon/Projects/hyperledger-fabric /home/shkwon/Projects/hyperledger-fabric"
   BE SURE THAT THE EXPORTED DIRECTORY AND MOUNTED DIRECTORY SHOULD BE SAME IN ABSOLUTE PATH.
3. Initialize the Docker swarm network with the following command.
   "docker swam init"
   And join the swam in the docker worker node with the worker join token.
   To know the worker join token, you need to run the following command from the manager node.
   "docker swarm join-token worker"
   Then, copy the output and paste it to the worker node terminal as command.
4. Run "networkUp.sh", "createChannel.sh" and "deployChaincode.sh" to make the network, channel, and 
   deploying "fabcar.go" chaincode.
5. To shutdown the whole network and clean the volumes and docker containers, you need to run the following command.
   "networkDown.sh" 

Enjoy... Bye.
