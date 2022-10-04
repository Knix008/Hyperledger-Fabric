#!/bin/bash
echo "Enrolling admin and creating wallet for appUser."
pushd util
node enrollAdmin.js
node registerUser.js
popd 

echo "Running node.js web server."
node fabcar.js