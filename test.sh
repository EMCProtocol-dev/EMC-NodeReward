dfx canister call --network test emc_token_dip20 mint "(principal \"2nkqu-ok25z-xaflo-ww4r6-jcjkt-at7yj-tzsho-424jf-6ynlm-jxq5n-qae\",100000000000000)"
dfx canister call --network test emc_token_dip20 approve "(principal \"bw4dl-smaaa-aaaaa-qaacq-cai\",100000000000000)"
dfx canister call --network test emc_node_reward stake "(10000000000000, 180, \"16Uiu2HAm8MbbU7Cge34Y17GXnMULjhyGHtMGUPXaGdepqUxn77M9\")"
dfx canister call --network test emc_node_reward stake "(20000000000000, 180, \"16Uiu2HAm8MbbU7Cge34Y17GXnMULjhyGHtMGUPXaGdepqUxn77M9\")"