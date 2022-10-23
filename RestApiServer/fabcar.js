'use strict';

var express = require('express');
var bodyParser = require('body-parser');
const fs = require('fs');

// Use express and body parser.
var app = express();
app.use(bodyParser.json());

// Setting the REST API Server port.
const port = process.env.PORT || 4000

// Setting for Hyperledger Fabric
const { Wallets, Gateway, Wallet } = require('fabric-network');
const path = require('path');
const ccpPath = path.resolve(__dirname, '.', 'connection', 'connection-org1.json');

// load the network configuration
let ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));
const walletPath = path.join(process.cwd(), 'wallets/wallet1');

app.get('/fabcar/queryallcars/', async function (req, res) {
    try {
        //console.log("Query All Cars.");
        // Create a new file system based wallet for managing identities.
        const wallet = await Wallets.newFileSystemWallet(walletPath);
        
        // Check to see if we've already enrolled the user.
        const identity = await wallet.get('appUser');
        if (!identity) {
            console.log('An identity for the user "appUser" does not exist in the wallet');
            console.log('Run the registerUser.js application before retrying');
            return;
        }
        
        // Use gateway for connecting to our peer node.
        const gateway = new Gateway();
        await gateway.connect(ccp, { wallet, identity: 'appUser', discovery: { enabled: true, asLocalhost: true } });
        
        // Get the network (channel) our contract is deployed to.
        const network = await gateway.getNetwork('mychannel');
        // Get the contract from the network.
        const contract = network.getContract('fabcar');

        // Send query.
        const result = await contract.evaluateTransaction('queryAllCars');
        res.status(200).json({response: result.toString()});
    } catch (error) {
        console.error(`Failed to evaluate transaction: ${error}`);
        res.status(500).json({error: error});
        //process.exit(1);
    }
});

app.get('/fabcar/query/:car_index', async function (req, res) {
    try {
        //console.log("Query a Car.");
        // Create a new file system based wallet for managing identities.
        const wallet = await Wallets.newFileSystemWallet(walletPath);
        
        // Check to see if we've already enrolled the user.
        const identity = await wallet.get('appUser');
        if (!identity) {
            console.log('An identity for the user "appUser" does not exist in the wallet');
            console.log('Run the registerUser.js application before retrying');
            return;
        }
        
        // Use gateway for connecting to our peer node.
        const gateway = new Gateway();
        await gateway.connect(ccp, { wallet, identity: 'appUser', discovery: { enabled: true, asLocalhost: true } });
        
        // Get the network (channel) our contract is deployed to.
        const network = await gateway.getNetwork('mychannel');
        // Get the contract from the network.
        const contract = network.getContract('fabcar');

        // Evaluate the specified transaction.
        //console.log('Car index : ' + req.params.car_index);
        const result = await contract.evaluateTransaction('queryCar', req.params.car_index);
        res.status(200).json({response: result.toString()});
    } catch (error) {
        console.error(`Failed to evaluate transaction: ${error}`);
        res.status(500).json({error: error});
        //process.exit(1);
    }
});

app.post('/fabcar/create/', async function (req, res) {
    try {
        //console.log("Create a Car.");
        // Create a new file system based wallet for managing identities.
        const wallet = await Wallets.newFileSystemWallet(walletPath);
        
        // Check to see if we've already enrolled the user.
        const identity = await wallet.get('appUser');
        if (!identity) {
            console.log('An identity for the user "appUser" does not exist in the wallet');
            console.log('Run the registerUser.js application before retrying');
            return;
        }
        
        // Use gateway for connecting to our peer node.
        const gateway = new Gateway();
        await gateway.connect(ccp, { wallet, identity: 'appUser', discovery: { enabled: true, asLocalhost: true } });
        
        // Get the network (channel) our contract is deployed to.
        const network = await gateway.getNetwork('mychannel');
        // Get the contract from the network.
        const contract = network.getContract('fabcar');

        // Submit the specified transaction.
        const result = await contract.submitTransaction('createCar', req.body.carid, req.body.make, req.body.model, req.body.colour, req.body.owner);
        res.status(200).send('TX success.');
        //res.send('Transaction has been submitted.');
        // Disconnect from the gateway.
        await gateway.disconnect();
    } catch (error) {
        console.error(`Failed to submit transaction: ${error}`);
        res.status(500).json({error: error});
        //process.exit(1);
    }
})

app.put('/fabcar/changeowner/', async function (req, res) {
    try {
        //console.log("Change Owner a Car.");
        // Create a new file system based wallet for managing identities.
        const wallet = await Wallets.newFileSystemWallet(walletPath);
        
        // Check to see if we've already enrolled the user.
        const identity = await wallet.get('appUser');
        if (!identity) {
            console.log('An identity for the user "appUser" does not exist in the wallet');
            console.log('Run the registerUser.js application before retrying');
            return;
        }
        
        // Use gateway for connecting to our peer node.
        const gateway = new Gateway();
        await gateway.connect(ccp, { wallet, identity: 'appUser', discovery: { enabled: true, asLocalhost: true } });
        
        // Get the network (channel) our contract is deployed to.
        const network = await gateway.getNetwork('mychannel');
        // Get the contract from the network.
        const contract = network.getContract('fabcar');

        // Submit the specified transaction.
        await contract.submitTransaction('changeCarOwner', req.body.carid, req.body.owner);
        res.status(200).send('Tx success.');
        //res.send('Transaction has been submitted.');
        // Disconnect from the gateway.
        await gateway.disconnect();
    } catch (error) {
        console.error(`Failed to submit transaction: ${error}`);
        res.status(500).json({error: error});
        //process.exit(1);
    }	
})

// custom 404 page
app.use((req, res) => {
    console.log("Cannot find web page!!!")
    res.type('text/plain')
    res.status(404)
    res.send('404 - Not Found')
})

// custom 500 page
app.use((err, req, res, next) => {
    console.error(err.message)
    res.type('text/plain')
    res.status(500)
    res.send('500 - Server Error')
})

app.listen(port, () => console.log(
    `REST API Server started on http://localhost:${port};\n` +
    `Press Ctrl-C to terminate.`))
