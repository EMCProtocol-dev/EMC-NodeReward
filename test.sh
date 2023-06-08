dfx identity use developer-testnet
dfx canister create --network test emc_node_reward
dfx deploy --network test emc_node_reward --argument="(\"be2us-64aaa-aaaaa-qaabq-cai\")" 

dfx canister call --network test emc_node_reward addValidator "(principal \"lsjqi-avt5t-ckuqr-t6tpg-lsmlg-4mokh-oimtq-godq4-gz6fa-362kl-hqe\")"
dfx canister call --network test emc_node_reward addValidator "(principal \"zqd7a-qbxzw-hehlk-j5yn5-llrs4-hhgjz-bk5cw-mkwe2-a4jb7-3u6xj-wae\")"
dfx canister call --network test emc_node_reward addValidator "(principal \"dhwpr-7ql5o-6jcud-kfvom-a3ywm-zd6uu-jkhmy-htgvd-u4xv4-a7cj3-oqe\")"
dfx canister call --network test emc_node_reward addValidator "(principal \"vnsdy-x67da-4iach-xtfzc-s6zzo-jt27w-t5i3g-ldqk4-gctbg-nqdcf-6ae\")"

dfx canister call --network test emc_token_dip20 mint "(principal \"2nkqu-ok25z-xaflo-ww4r6-jcjkt-at7yj-tzsho-424jf-6ynlm-jxq5n-qae\",100000000000000)"
dfx canister call --network test emc_token_dip20 approve "(principal \"bw4dl-smaaa-aaaaa-qaacq-cai\",100000000000000)"

dfx canister call --network test emc_node_reward stake "(10000000000000, 180, \"16Uiu2HAmQkbuGb3K3DmCyEDvKumSVCphVJCGPGHNoc4CobJbxfsC\")"
dfx canister call --network test emc_node_reward myStake "(\"16Uiu2HAmQkbuGb3K3DmCyEDvKumSVCphVJCGPGHNoc4CobJbxfsC\")"

dfx canister call --network test emc_node_reward stake "(20000000000000, 180, \"16Uiu2HAm8MbbU7Cge34Y17GXnMULjhyGHtMGUPXaGdepqUxn77M9\")"

dfx canister call --network test emc_node_reward launchRewardTask

dfx canister call --network test emc_node_reward withdrawTo "(principal \"2nkqu-ok25z-xaflo-ww4r6-jcjkt-at7yj-tzsho-424jf-6ynlm-jxq5n-qae\")"



#on IC
#================================
dfx identity use emc-developer-eric
dfx canister create --network ic emc_node_reward
dfx deploy --network ic emc_node_reward --argument="(\"aeex5-aqaaa-aaaam-abm3q-cai\")" 

#add validators
dfx canister call --network ic emc_node_reward addValidator "(principal \"j7i3j-zejlu-4rlei-ovmir-ica3h-synrc-4tn3d-hpavk-agxsm-pitnt-jqe\")"
dfx canister call --network ic emc_node_reward addValidator "(principal \"agfom-wrooe-5yazn-a7pf5-i56nk-wcqtt-x5vcd-awhvo-fuy4l-eya62-eqe\")"
dfx canister call --network ic emc_node_reward addValidator "(principal \"xdzzt-d3g6i-v2wro-a5he2-6kxjj-cqt25-6a2yq-odsdp-mang6-okm6l-4ae\")"
dfx canister call --network ic emc_node_reward addValidator "(principal \"ethj3-erevb-25awk-i6677-xt53i-gn5ps-ivevt-nkm45-mdfn2-4nzdj-kae\")"
dfx canister call --network ic emc_node_reward addValidator "(principal \"ic6xe-iseyq-byiiy-trrd3-jnhxy-zem2j-5egs2-guwb4-npjwj-a3fub-tqe\")"
dfx canister call --network ic emc_node_reward addValidator "(principal \"3pd6m-kbkv3-wsxif-d6ist-a5wiu-zyl2o-h7cm5-vuhrv-xsczs-hx55q-uae\")"
dfx canister call --network ic emc_node_reward addValidator "(principal \"tetml-zqesn-ff26u-krua3-zn4yk-uxjt5-a35v6-ev32c-ockb2-cqvvy-xae\")"
dfx canister call --network ic emc_node_reward launchRewardTask