#!/bin/bash
# Kiichain testnet oro chain.

PRIV_VALIDATOR_KEY_FILE=${1:-"$HOME/priv_validator_key.json"}
NODE_KEY_FILE=${2:-"$HOME/node_key.json"}
NODE_HOME=~/.kiichain3
NODE_MONIKER=your_moniker
SERVICE_NAME=kiichaind
SERVICE_VERSION="v3.0.0"
KIICHAIN_PORT="12"

CHAIN_BINARY='kiichaind'
CHAIN_ID=kiichain3

# Persistent peers and RPC endpoints
PERSISTENT_PEERS="5b6aa55124c0fd28e47d7da091a69973964a9fe1@uno.sentry.testnet.v3.kiivalidator.com:26656,5e6b283c8879e8d1b0866bda20949f9886aff967@dos.sentry.testnet.v3.kiivalidator.com:26656"
PRIMARY_ENDPOINT=https://rpc.uno.sentry.testnet.v3.kiivalidator.com
SECONDARY_ENDPOINT=https://rpc.dos.sentry.testnet.v3.kiivalidator.com

# The genesis for the chain
GENESIS_URL=https://raw.githubusercontent.com/KiiChain/testnets/refs/heads/main/testnet_oro/genesis.json

# Install wget, git and jq
sudo apt update
sudo apt-get install git jq curl wget -y

# Stop service if exists
systemctl --user stop $SERVICE_NAME.service

# Install go 1.22
echo "Installing go..."
rm go*linux-amd64.tar.gz
wget https://go.dev/dl/go1.22.10.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.10.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile

# Install Kiichain binary
echo "Installing build-essential..."
sudo apt install build-essential -y
echo "Installing Kiichain..."
cd $HOME
mkdir -p $HOME/go/bin
rm -rf kiichain
git clone https://github.com/KiiChain/kiichain.git
cd kiichain
git checkout $SERVICE_VERSION
make install
export PATH=$PATH:$HOME/go/bin
echo 'export PATH=$PATH:$HOME/go/bin' >> ~/.profile

# Initialize home directory
echo "Initializing $NODE_HOME..."
cd $HOME
rm -rf $NODE_HOME
$CHAIN_BINARY config chain-id $CHAIN_ID --home $NODE_HOME
$CHAIN_BINARY config keyring-backend test --home $NODE_HOME
$CHAIN_BINARY config broadcast-mode block --home $NODE_HOME
$CHAIN_BINARY init $NODE_MONIKER --chain-id $CHAIN_ID --home $NODE_HOME

# set custom ports in app.toml
sed -i.bak -e "s%:1317%:${KIICHAIN_PORT}317%g;
s%:8080%:${KIICHAIN_PORT}080%g;
s%:9090%:${KIICHAIN_PORT}090%g;
s%:9091%:${KIICHAIN_PORT}091%g;
s%:8545%:${KIICHAIN_PORT}545%g;
s%:8546%:${KIICHAIN_PORT}546%g;
s%:6065%:${KIICHAIN_PORT}065%g" $NODE_HOME/config/app.toml

# set custom ports in config.toml file
sed -i.bak -e "s%:26658%:${KIICHAIN_PORT}658%g;
s%:26657%:${KIICHAIN_PORT}657%g;
s%:6060%:${KIICHAIN_PORT}060%g;
s%:26656%:${KIICHAIN_PORT}656%g;
s%^external_address = \"\"%external_address = \"$(wget -qO- eth0.me):${KIICHAIN_PORT}656\"%;
s%:26660%:${KIICHAIN_PORT}660%g" $NODE_HOME/config/config.toml

# set custom ports in client.toml file
sed -i.bak -e "s%:26657%:${KIICHAIN_PORT}657%g" $NODE_HOME/config/client.toml

# Set the PERSISTENT_PEERS
sed -i -e "/persistent-peers =/ s^= .*^= \"$PERSISTENT_PEERS\"^" $NODE_HOME/config/config.toml

# Configure state-sync
TRUST_HEIGHT_DELTA=500
LATEST_HEIGHT=$(curl -s "$PRIMARY_ENDPOINT"/block | jq -r ".block.header.height")
if [[ "$LATEST_HEIGHT" -gt "$TRUST_HEIGHT_DELTA" ]]; then
SYNC_BLOCK_HEIGHT=$(($LATEST_HEIGHT - $TRUST_HEIGHT_DELTA))
else
SYNC_BLOCK_HEIGHT=$LATEST_HEIGHT
fi

# Get the sync block hash
SYNC_BLOCK_HASH=$(curl -s "$PRIMARY_ENDPOINT/block?height=$SYNC_BLOCK_HEIGHT" | jq -r ".block_id.hash")

# Enable state sync
sed -i.bak -e "s|^enable *=.*|enable = true|" $NODE_HOME/config/config.toml
sed -i.bak -e "s|^rpc-servers *=.*|rpc-servers = \"$PRIMARY_ENDPOINT,$SECONDARY_ENDPOINT\"|" $NODE_HOME/config/config.toml
sed -i.bak -e "s|^db-sync-enable *=.*|db-sync-enable = false|" $NODE_HOME/config/config.toml
sed -i.bak -e "s|^trust-height *=.*|trust-height = $SYNC_BLOCK_HEIGHT|" $NODE_HOME/config/config.toml
sed -i.bak -e "s|^trust-hash *=.*|trust-hash = \"$SYNC_BLOCK_HASH\"|" $NODE_HOME/config/config.toml

# Set the node as validator
sed -i 's/mode = "full"/mode = "validator"/g' $NODE_HOME/config/config.toml

# Enable DB
sed -i.bak -e "s|^occ-enabled *=.*|occ-enabled = true|" $NODE_HOME/config/app.toml
sed -i.bak -e "s|^sc-enable *=.*|sc-enable = true|" $NODE_HOME/config/app.toml
sed -i.bak -e "s|^ss-enable *=.*|ss-enable = true|" $NODE_HOME/config/app.toml
sed -i.bak -e 's/^# concurrency-workers = 20$/concurrency-workers = 500/' $NODE_HOME/config/app.toml

# Replace genesis file
echo "Replacing genesis file..."
wget $GENESIS_URL -O genesis.json
mv genesis.json $NODE_HOME/config/genesis.json

# Replace keys
echo "Replacing keys..."
cp $PRIV_VALIDATOR_KEY_FILE $NODE_HOME/config/priv_validator_key.json
cp $NODE_KEY_FILE $NODE_HOME/config/node_key.json

# Create the service
echo "Creating $SERVICE_NAME.service..."
sudo rm /etc/systemd/system/$SERVICE_NAME.service
sudo touch /etc/systemd/system/$SERVICE_NAME.service

echo "[Unit]"                               | sudo tee /etc/systemd/system/$SERVICE_NAME.service
echo "Description=$SERVICE_NAME service"        | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "After=network-online.target"          | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo ""                                     | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "[Service]"                            | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "User=$USER"                           | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "ExecStart=$HOME/go/bin/$CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $NODE_HOME --chain-id $CHAIN_ID" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "Restart=always"                       | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "RestartSec=3"                         | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "LimitNOFILE=4096"                     | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo ""                                     | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "[Install]"                            | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "WantedBy=multi-user.target"           | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a

# Start service
sudo systemctl daemon-reload

# Enable and start the service after the genesis that includes the CCV state is in place
sudo systemctl enable $SERVICE_NAME.service
sudo systemctl start $SERVICE_NAME.service
sudo systemctl restart systemd-journald

# Add Kiichaind to the path
echo "Setting up path for Kiichaind bin..."
echo "export PATH=$PATH:$HOME/go/bin:" >> .profile

echo "***********************"
echo "To see the service log enter:"
echo "journalctl -fu $SERVICE_NAME.service"
echo "***********************"

# Get the env vars
source ~/.profile

journalctl -u $SERVICE_NAME.service -fo cat
