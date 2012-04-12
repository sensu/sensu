#!/bin/sh
function clean {
rm -f ./client/*
rm -f ./server/*
rm -f ./testca/cacert*
rm -f ./testca/index.txt.*
rm -f ./testca/private/*
rm -f ./testca/serial.old
rm -f ./testca/certs/*
rm -f ./testca/index.txt
rm -f ./testca/serial
}

function generate {
mkdir -p ./client ./server ./testca/private ./testca/certs
touch testca/index.txt
echo 01 > testca/serial
cd testca
openssl req -x509 -config openssl.cnf -newkey rsa:2048 -days 40000 -out cacert.pem -outform PEM -subj /CN=TestCA/ -nodes
openssl x509 -in cacert.pem -out cacert.cer -outform DER
cd ../server
openssl genrsa -out key.pem 2048
openssl req -new -key key.pem -out req.pem -outform PEM -subj /CN=$(hostname)/O=server/ -nodes
cd ../testca
openssl ca -config openssl.cnf -in ../server/req.pem -out ../server/cert.pem -notext -batch -extensions server_ca_extensions
cd ../server
openssl pkcs12 -export -out keycert.p12 -in cert.pem -inkey key.pem -passout pass:DemoPass
cd ../client
openssl genrsa -out key.pem 2048
openssl req -new -key key.pem -out req.pem -outform PEM -subj /CN=$(hostname)/O=client/ -nodes
cd ../testca
openssl ca -config openssl.cnf -in ../client/req.pem -out ../client/cert.pem -notext -batch -extensions client_ca_extensions
cd ../client
openssl pkcs12 -export -out keycert.p12 -in cert.pem -inkey key.pem -passout pass:DemoPass

cd ../
./generate_databag.rb
}

if [ "$1" = "generate" ]; then 
  echo "Generating ssl certificates..."
  generate
  exit
elif [ "$1" = "clean" ]; then
  echo "Cleaning up previously generated certificates..."
  clean
else
  echo "You must run the script with either generate or clean, e.g. ./ssl_certs.sh generate"
fi
