This folder will have caliper examples files.

** Instruction : 
1. mkdir caliper-workspace
2. cd caliper-workspace
3. mkdir networks
4. mkdir benchmarks
5. mkdir workload
6. npm install --only=prod @hyperledger/caliper-cli@0.4.2  --> for Fabric 2.2.X (npm install --only=prod @hyperledger/caliper-cli@0.5.0  --> for Fabric 2.4.X)
7. npx caliper bind --caliper-bind-sut fabric:2.2 --> for Fabric 2.2.X (npx caliper bind --caliper-bind-sut fabric:2.4 --> for Fabric 2.4.X)
8. npx caliper launch manager --caliper-workspace ./ --caliper-networkconfig networks/networkConfig.yaml --caliper-benchconfig benchmarks/myAssetBenchmark.yaml --caliper-flow-only-test --caliper-fabric-gateway-enabled


** Caliper v0.5.0 
Run "npx caliper launch manager --caliper-workspace ./ --caliper-networkconfig networks/fabric/test-network.yaml --caliper-benchconfig benchmarks/samples/fabric/fabcar/config.yaml --caliper-flow-only-test --caliper-fabric-gateway-enabled" command.

