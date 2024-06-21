#!/bin/bash

while true
do

# Menu

PS3='Select an action: '
options=(
"Install"
"Create Wallet"
"Create Validator"
"Exit")
select opt in "${options[@]}"
do
case $opt in

"Install")
echo "============================================================"
echo "Install start"
echo "============================================================"

# set vars
if [ ! $NODENAME ]; then
	read -p "Enter node name: " NODENAME
	echo 'export NODENAME='$NODENAME >> $HOME/.bash_profile
fi
if [ ! $WALLET ]; then
	echo "export WALLET=wallet" >> $HOME/.bash_profile
fi
echo "export FAIRBLOCK_CHAIN_ID=fairyring-testnet-1" >> $HOME/.bash_profile
source $HOME/.bash_profile

# update
sudo apt update && sudo apt upgrade -y

# packages
apt install curl iptables build-essential git wget jq make gcc nano tmux htop nvme-cli pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev zstd -y

# install go
if ! [ -x "$(command -v go)" ]; then
ver="1.21.3" && \
wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz" && \
sudo rm -rf /usr/local/go && \
sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz" && \
rm "go$ver.linux-amd64.tar.gz" && \
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> $HOME/.bash_profile && \
source $HOME/.bash_profile
fi

# download binary
cd $HOME && rm -rf fairyring
git clone https://github.com/Fairblock/fairyring.git
cd fairyring
git checkout v0.5.0
make install

# config
fairyringd config chain-id $FAIRBLOCK_CHAIN_ID
fairyringd config keyring-backend test

# init
fairyringd init $NODENAME --chain-id $FAIRBLOCK_CHAIN_ID

# download genesis and addrbook
curl -L https://raw.githubusercontent.com/Fairblock/fairyring/main/networks/testnets/fairyring-testnet-1/genesis.json > $HOME/.fairyring/config/genesis.json
curl -L https://s3.imperator.co/testnets-addrbook/fairblock/addrbook.json > $HOME/.fairyring/config/addrbook.json

# set minimum gas price
#sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"20000000000ufairy\"|" $HOME/.fairyring/config/app.toml

# set peers and seeds
SEEDS=""
PEERS="51ac0d0e0b253c5fbb5737422bd94f3d0c51599d@135.181.216.54:3440,a7f7f32d7d1986999338da8a0aa61985a44238da@159.69.83.97:26665,7d422b5a4ef9503b3acc3904f8abb071cf596629@88.218.226.23:26656,99b3d5ec3a9f14b027e5c8ef7879b4fc5f1b5fb4@162.19.70.182:26656,593e4ce668b3fd05541b8e2ee88764cba4b26af6@80.64.208.224:26656,3cda3bebf7aaeeb0533734496158420dcd3da4ad@94.130.137.119:26666,ca49cba70229fe3d0cac2b992d0f96aae7708759@34.66.108.187:26656,cd1cbf64a3e85d511c2a40b9e3e7b2e9b40d5905@18.183.243.242:26656,12f315956f97ba54f8a6e61d85e5efd4e8fb735e@51.210.222.119:26656,5ec4190a29fb500d3416f06ea0d1245545859681@160.202.128.199:56196"
sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.fairyring/config/config.toml

# disable indexing
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $HOME/.fairyring/config/config.toml

# config pruning
pruning="custom"
pruning_keep_recent="100"
pruning_keep_every="0"
pruning_interval="10"
sed -i -e "s/^pruning *=.*/pruning = \"$pruning\"/" $HOME/.fairyring/config/app.toml
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"$pruning_keep_recent\"/" $HOME/.fairyring/config/app.toml
sed -i -e "s/^pruning-keep-every *=.*/pruning-keep-every = \"$pruning_keep_every\"/" $HOME/.fairyring/config/app.toml
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"$pruning_interval\"/" $HOME/.fairyring/config/app.toml
sed -i "s/snapshot-interval *=.*/snapshot-interval = 0/g" $HOME/.fairyring/config/app.toml

# enable prometheus
sed -i -e "s/prometheus = false/prometheus = true/" $HOME/.fairyring/config/config.toml

# create service
sudo tee /etc/systemd/system/fairyringd.service > /dev/null <<EOF
[Unit]
Description=fairyringd Daemon
After=network-online.target
[Service]
User=$USER
ExecStart=$(which fairyringd) start
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

# reset
fairyringd tendermint unsafe-reset-all --home $HOME/.fairyring --keep-addr-book
wget -O fairblock_760269.tar.zst https://s3.imperator.co/testnets-snapshots/fairblock/fairblock_760269.tar.zst
zstd -d --stdout fairblock_760269.tar.zst | tar xf - -C $HOME/.fairyring

# start service
sudo systemctl daemon-reload
sudo systemctl enable fairyringd
sudo systemctl restart fairyringd

break
;;

"Create Wallet")
fairyringd keys add $WALLET
echo "============================================================"
echo "Save address and mnemonic"
echo "============================================================"
FAIRBLOCK_WALLET_ADDRESS=$(fairyringd keys show $WALLET -a)
FAIRBLOCK_VALOPER_ADDRESS=$(fairyringd keys show $WALLET --bech val -a)
echo 'export FAIRBLOCK_WALLET_ADDRESS='${FAIRBLOCK_WALLET_ADDRESS} >> $HOME/.bash_profile
echo 'export FAIRBLOCK_VALOPER_ADDRESS='${FAIRBLOCK_VALOPER_ADDRESS} >> $HOME/.bash_profile
source $HOME/.bash_profile

break
;;

"Create Validator")
fairyringd tx staking create-validator \
--amount=10000000000ufairy \
--pubkey=$(fairyringd tendermint show-validator) \
--moniker=$NODENAME \
--chain-id=fairyring-testnet-1 \
--commission-rate=0.10 \
--commission-max-rate=0.20 \
--commission-max-change-rate=0.01 \
--min-self-delegation=1 \
--from=wallet \
--gas=300000 \
-y
  
break
;;

"Exit")
exit
;;
*) echo "invalid option $REPLY";;
esac
done
done
