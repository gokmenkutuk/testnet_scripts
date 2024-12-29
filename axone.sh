#!/bin/bash

# Prompt user for nodename and port prefix
read -p "Enter the nodename: " NODENAME
read -p "Enter the custom port prefix (e.g., 176): " PORT_PREFIX

# Install dependencies for building from source
sudo apt update
sudo apt install -y curl git jq lz4 build-essential

# Install Go
sudo rm -rf /usr/local/go
curl -L https://go.dev/dl/go1.22.7.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.profile
source $HOME/.profile

# Clone project repository
cd && rm -rf axoned
git clone https://github.com/axone-protocol/axoned
cd axoned
git checkout v10.0.0

# Build binary
make install

# Prepare cosmovisor directories
mkdir -p $HOME/.axoned/cosmovisor/genesis/bin
ln -s $HOME/.axoned/cosmovisor/genesis $HOME/.axoned/cosmovisor/current -f

# Copy binary to cosmovisor directory
cp $(which axoned) $HOME/.axoned/cosmovisor/genesis/bin

# Set node CLI configuration
axoned config chain-id axone-dentrite-1
axoned config keyring-backend test
axoned config node tcp://localhost:${PORT_PREFIX}57

# Initialize the node
axoned init "$NODENAME" --chain-id axone-dentrite-1

# Download genesis and addrbook files
curl -L https://snapshots-testnet.nodejumper.io/axone/genesis.json > $HOME/.axoned/config/genesis.json
curl -L https://snapshots-testnet.nodejumper.io/axone/addrbook.json > $HOME/.axoned/config/addrbook.json

# Set seeds
sed -i -e 's|^seeds *=.*|seeds = "3f472746f46493309650e5a033076689996c8881@axone-testnet.rpc.kjnodes.com:13659"|' $HOME/.axoned/config/config.toml

# Set minimum gas price
sed -i -e 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.001uaxone"|' $HOME/.axoned/config/app.toml

# Set pruning
sed -i \
  -e 's|^pruning *=.*|pruning = "custom"|' \
  -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
  -e 's|^pruning-interval *=.*|pruning-interval = "17"|' \
  $HOME/.axoned/config/app.toml

# Enable prometheus
sed -i -e 's|^prometheus *=.*|prometheus = true|' $HOME/.axoned/config/config.toml

# Change ports dynamically
sed -i -e "s%:1317%:${PORT_PREFIX}17%; s%:8080%:${PORT_PREFIX}80%; s%:9090%:${PORT_PREFIX}90%; s%:9091%:${PORT_PREFIX}91%; s%:8545%:${PORT_PREFIX}45%; s%:8546%:${PORT_PREFIX}46%; s%:6065%:${PORT_PREFIX}65%" $HOME/.axoned/config/app.toml
sed -i -e "s%:26658%:${PORT_PREFIX}58%; s%:26657%:${PORT_PREFIX}57%; s%:6060%:${PORT_PREFIX}60%; s%:26656%:${PORT_PREFIX}56%; s%:26660%:${PORT_PREFIX}61%" $HOME/.axoned/config/config.toml

# Download latest chain data snapshot
curl "https://snapshots-testnet.nodejumper.io/axone/axone_latest.tar.lz4" | lz4 -dc - | tar -xf - -C "$HOME/.axoned"

# Install Cosmovisor
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.7.0

# Create a service
sudo tee /etc/systemd/system/axone.service > /dev/null << EOF
[Unit]
Description=Axone node service
After=network-online.target
[Service]
User=$USER
WorkingDirectory=$HOME/.axoned
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/.axoned"
Environment="DAEMON_NAME=axoned"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=true"
[Install]
WantedBy=multi-user.target
EOF

# Reload and enable the service
sudo systemctl daemon-reload
sudo systemctl enable axone.service

# Start the service and check the logs
sudo systemctl start axone.service
sudo journalctl -u axone.service -f --no-hostname -o cat
