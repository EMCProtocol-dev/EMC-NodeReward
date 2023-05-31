dfx identity use developer-testnet
dfx canister create --network ic emc_node_reward
dfx deploy --network ic emc_node_reward --argument="(\"be2us-64aaa-aaaaa-qaabq-cai\")" 

dfx canister call --network test emc_token_dip20 mint "(principal \"2nkqu-ok25z-xaflo-ww4r6-jcjkt-at7yj-tzsho-424jf-6ynlm-jxq5n-qae\",100000000000000)"
dfx canister call --network test emc_token_dip20 approve "(principal \"bw4dl-smaaa-aaaaa-qaacq-cai\",100000000000000)"

dfx canister call --network test emc_node_reward stake "(10000000000000, 180, \"16Uiu2HAmQkbuGb3K3DmCyEDvKumSVCphVJCGPGHNoc4CobJbxfsC\")"
dfx canister call --network test emc_node_reward myStake "(\"16Uiu2HAmQkbuGb3K3DmCyEDvKumSVCphVJCGPGHNoc4CobJbxfsC\")"

dfx canister call --network test emc_node_reward stake "(20000000000000, 180, \"16Uiu2HAm8MbbU7Cge34Y17GXnMULjhyGHtMGUPXaGdepqUxn77M9\")"

dfx canister call --network test emc_node_reward launchRewardTask


#on IC
dfx identity use emc-developer-eric
dfx canister create --network ic emc_node_reward
dfx deploy --network ic emc_node_reward --argument="(\"aeex5-aqaaa-aaaam-abm3q-cai\")" 
