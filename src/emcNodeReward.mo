/**
 * Module     : emcNodeReward.mo
 * Copyright  : 2021 EMC Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : EMC Team <dev@emc.app>
 * Stability  : Experimental
 */

import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Order "mo:base/Order";
import TrieMap "mo:base/TrieMap";
import Hash "mo:base/Hash";
import Int "mo:base/Int";
import Float "mo:base/Float";
import emc_token_dip20 "emc_token_dip20";
import emcNode "emcNode";
import emcReward "emcReward";
import Timer "mo:base/Timer";
import Nat32 "mo:base/Nat32";
import Bool "mo:base/Bool";
import Trie "mo:base/Trie";

shared (msg) actor class EmcNodeReward(
    token : Text
) = self {
    // returns result
    public type emcResult = {
        #Ok : Nat;
        #Err : {
            #NodeAlreadyExist;
            #NodeNotExist;
            #UnknowType;
            #CallerNotAuthorized;
            #NotAValidator;
            #DuplicatedValidation;
            #TokenTransferFailed;
            #StakedBefore;
            #StakeTooShort;
            #StakeNotEnough;
            #NoStakeFound;
            #CanNotUnstake;
        };
    };

    private var dayNanos : Nat = 1_000_000_000 * 3600 * 24;
    private var secNanos : Nat = 1_000_000_000;
    private var daySeconds : Nat = 3600 * 24;
    private var hourSeconds : Nat = 3600;
    private var emcDecimals : Nat = 100_000_000;

    private stable var owner : Principal = msg.caller;

    private stable var dayValidationRounds : Nat = 96;
    private stable var testnetRunning : Bool = true;
    private stable var rewardPoolBalance : Nat = 300_000_000_000_000;
    private stable var totalStaking : Nat = 0;
    private stable var totalReward : Nat = 0;
    private stable var totalDistributed : Nat = 0;

    private var NodeRouter : Nat = 0;
    private var NodeValidator : Nat = 1;
    private var NodeComputing : Nat = 2;

    //node and validation
    type Node = emcNode.Node;
    type NodeType = Nat;
    type NodeValidationRequest = emcNode.NodeValidationRequest;
    type NodeValidationUnit = emcNode.NodeValidationUnit;
    type NodeValidationPool = HashMap.HashMap<Text, HashMap.HashMap<Text, NodeValidationUnit>>;

    private func account_key(t : Principal) : Trie.Key<Principal> = {
        key = t;
        hash = Principal.hash t;
    };

    private func text_key(t : Text) : Trie.Key<Text> = {
        key = t;
        hash = Text.hash t;
    };

    private stable var nodeEntries : [(Text, Node)] = [];
    private stable var validatorEntries : [(Principal, Time.Time)] = [];
    private stable var validationPoolEntries : [(Int, [(Text, [(Text, NodeValidationUnit)])])] = [];

    private stable var computingNodes = Trie.empty<Text, Node>();
    private stable var validatorNodes = Trie.empty<Text, Node>();
    private stable var routerNodes = Trie.empty<Text, Node>();

    private stable var validators = Trie.empty<Principal, Time.Time>();
    private stable var routers = Trie.empty<Principal, Time.Time>();

    private var validationPools = TrieMap.TrieMap<Int, NodeValidationPool>(Int.equal, Int.hash);

    //node staking
    private var tokenCanister : emc_token_dip20.Token = actor (token);
    private stable var stakePoolEntires : [(Text, emcReward.StakeRecord)] = [];
    private stable var stakePool = Trie.empty<Text, emcReward.StakeRecord>();

    //reward definations
    type NodeRewardRecordPool = HashMap.HashMap<Text, emcReward.RewardRecord>;

    private var timerID : Nat = 0;
    private stable var startDay : Nat = Int.abs(Time.now() / dayNanos);

    private stable var rewardPoolsEntries : [(Int, [(Principal, emcReward.RewardRecord)])] = [];
    private stable var failedRewardEntries : [(Text, emcReward.FailedReward)] = [];
    private stable var rewardStatusEntries : [(Text, emcReward.RewardStatus)] = [];

    private var rewardPools = TrieMap.TrieMap<Int, NodeRewardRecordPool>(Int.equal, Int.hash);
    private stable var failedRewardPool = Trie.empty<Text, emcReward.FailedReward>();
    private stable var rewardStatus = Trie.empty<Text, emcReward.RewardStatus>();

    public shared (msg) func stopTestnet() : async emcResult {
        assert (msg.caller == owner);
        testnetRunning := false;
        return #Ok(0);
    };

    public shared (msg) func startTestnet() : async emcResult {
        assert (msg.caller == owner);
        testnetRunning := true;
        startDay := Int.abs(Time.now() / dayNanos);
        return #Ok(0);
    };

    /**
* validators
**/

    public shared (msg) func addValidator(_validator : Principal) : async emcResult {
        if (msg.caller != owner) {
            return #Err(#CallerNotAuthorized);
        };

        if (Trie.get(validators, account_key(_validator), Principal.equal) != null) {
            return #Err(#NodeAlreadyExist);
        };

        validators := Trie.put(validators, account_key(_validator), Principal.equal, Time.now()).0;

        return #Ok(0);

    };

    public shared (msg) func removeValidator(_validator : Principal) : async emcResult {
        if (msg.caller != owner) {
            return #Err(#CallerNotAuthorized);
        };

        validators := Trie.remove(validators, account_key(_validator), Principal.equal).0;

        return #Ok(0);

    };

    public shared query (msg) func listValidators() : async [(Principal, Time.Time)] {
        Trie.toArray<Principal, Time.Time, (Principal, Time.Time)>(
            validators,
            func(k, v) = (k, v),
        );
    };

    private func isValidator(who : Principal) : Bool {
        if (Trie.get(validators, account_key(who), Principal.equal) != null) {
            return true;
        } else {
            return false;
        };
    };

    public query func isValidatorPrincipal(who : Principal) : async Bool {
        if (isValidator(who)) {
            return true;
        } else {
            return false;
        };
    };

    /**
* routers
**/
    public shared (msg) func addRouter(_router : Principal) : async emcResult {
        if (msg.caller != owner) {
            return #Err(#CallerNotAuthorized);
        };

        if (Trie.get(routers, account_key(_router), Principal.equal) != null) {
            return #Err(#NodeAlreadyExist);
        };

        routers := Trie.put(routers, account_key(_router), Principal.equal, Time.now()).0;

        return #Ok(0);

    };

    public shared (msg) func removeRouter(_router : Principal) : async emcResult {
        if (msg.caller != owner) {
            return #Err(#CallerNotAuthorized);
        };

        routers := Trie.remove(routers, account_key(_router), Principal.equal).0;

        return #Ok(0);

    };

    public shared query (msg) func listRouters() : async [(Principal, Time.Time)] {
        Trie.toArray<Principal, Time.Time, (Principal, Time.Time)>(
            routers,
            func(k, v) = (k, v),
        );
    };

    public query func isRouter(who : Principal) : async Bool {
        if (Trie.get(routers, account_key(who), Principal.equal) != null) {
            return true;
        } else {
            return false;
        };
    };

    /**
* Nodes
**/

    public shared (msg) func registerValidatorNode(_nodeID : Text, _wallet : Principal) : async emcResult {
        if (Trie.get(validators, account_key(msg.caller), Principal.equal) == null) {
            return #Err(#CallerNotAuthorized);
        };

        if (Trie.get(validatorNodes, text_key(_nodeID), Text.equal) != null) {
            return #Err(#NodeAlreadyExist);
        };

        let tmp : Node = {
            nodeType = NodeValidator;
            nodeID = _nodeID;
            owner = msg.caller;
            wallet = _wallet;
            registered = Time.now();
        };
        validatorNodes := Trie.put(validatorNodes, text_key(_nodeID), Text.equal, tmp).0;
        return #Ok(0);
    };

    public shared (msg) func unregisterValidatorNode(_nodeID : Text) : async emcResult {
        switch (Trie.get(validatorNodes, text_key(_nodeID), Text.equal)) {
            case (?node) {
                if (node.owner != msg.caller) {
                    return #Err(#CallerNotAuthorized);
                } else {
                    validatorNodes := Trie.remove(validatorNodes, text_key(_nodeID), Text.equal).0;
                    return #Ok(0);
                };
            };
            case (_) {
                return #Err(#NodeNotExist);
            };
        };
    };

    public shared query (msg) func listValidatorNodes() : async [Node] {
        Trie.toArray<Text, Node, Node>(
            validatorNodes,
            func(k, v) = v,
        );
    };

    private func isValidatorNode(_nodeID : Text) : Bool {
        if (Trie.get(validatorNodes, text_key(_nodeID), Text.equal) != null) {
            return true;
        } else {
            return false;
        };
    };

    public shared (msg) func registerRouterNode(_nodeID : Text, _wallet : Principal) : async emcResult {
        if (Trie.get(routers, account_key(msg.caller), Principal.equal) == null) {
            return #Err(#CallerNotAuthorized);
        };

        if (Trie.get(routerNodes, text_key(_nodeID), Text.equal) != null) {
            return #Err(#NodeAlreadyExist);
        };

        let tmp : Node = {
            nodeType = NodeRouter;
            nodeID = _nodeID;
            owner = msg.caller;
            wallet = _wallet;
            registered = Time.now();
        };
        routerNodes := Trie.put(routerNodes, text_key(_nodeID), Text.equal, tmp).0;
        return #Ok(0);
    };

    public shared (msg) func unregisterRouterNode(_nodeID : Text) : async emcResult {
        switch (Trie.get(routerNodes, text_key(_nodeID), Text.equal)) {
            case (?node) {
                if (node.owner != msg.caller) {
                    return #Err(#CallerNotAuthorized);
                } else {
                    routerNodes := Trie.remove(routerNodes, text_key(_nodeID), Text.equal).0;
                    return #Ok(0);
                };
            };
            case (_) {
                return #Err(#NodeNotExist);
            };
        };
    };

    public shared query (msg) func listRouterNodes() : async [Node] {
        Trie.toArray<Text, Node, Node>(
            routerNodes,
            func(k, v) = v,
        );
    };

    private func isRouterNode(_nodeID : Text) : Bool {
        if (Trie.get(routerNodes, text_key(_nodeID), Text.equal) != null) {
            return true;
        } else {
            return false;
        };
    };

    public shared (msg) func registerComputingNode(_nodeID : Text, _wallet : Principal) : async emcResult {
        if (Trie.get(computingNodes, text_key(_nodeID), Text.equal) != null) {
            return #Err(#NodeAlreadyExist);
        };

        let tmp : Node = {
            nodeType = NodeComputing;
            nodeID = _nodeID;
            owner = msg.caller;
            wallet = _wallet;
            registered = Time.now();
        };
        computingNodes := Trie.put(computingNodes, text_key(_nodeID), Text.equal, tmp).0;
        return #Ok(0);
    };

    public shared (msg) func unregisterComputingNode(_nodeID : Text) : async emcResult {
        switch (Trie.get(computingNodes, text_key(_nodeID), Text.equal)) {
            case (?node) {
                if (node.owner != msg.caller) {
                    return #Err(#CallerNotAuthorized);
                } else {
                    computingNodes := Trie.remove(computingNodes, text_key(_nodeID), Text.equal).0;
                    return #Ok(0);
                };
            };
            case (_) {
                return #Err(#NodeNotExist);
            };
        };
    };

    public shared query (msg) func listComputingNodes(start : Nat, length : Nat) : async [Node] {
        let array = Trie.toArray<Text, Node, Node>(
            computingNodes,
            func(k, v) = v,
        );
        if (start >= Array.size(array)) {
            return [];
        } else if (start + length > Array.size(array)) {
            return Array.subArray(array, start, Array.size(array) - start);
        } else {
            return Array.subArray(array, start, length);
        };
    };

    private func isComputingNode(_nodeID : Text) : Bool {
        if (Trie.get(computingNodes, text_key(_nodeID), Text.equal) != null) {
            return true;
        } else {
            return false;
        };
    };

    private func getNodeByID(_nodeID : Text) : ?Node {
        var node = Trie.get(computingNodes, text_key(_nodeID), Text.equal);
        if (node != null) {
            return node;
        };

        node := Trie.get(validatorNodes, text_key(_nodeID), Text.equal);
        if (node != null) {
            return node;
        };

        node := Trie.get(routerNodes, text_key(_nodeID), Text.equal);
        if (node != null) {
            return node;
        };

        return null;
    };

    public shared query (msg) func myNode(_nodeID : Text) : async [Node] {
        switch (getNodeByID(_nodeID)) {
            case (?node) {
                return [node];
            };
            case (_) {
                return [];
            };
        };
    };

    private func getNodePrincipal(_nodeID : Text) : ?Principal {
        switch (Trie.get(computingNodes, text_key(_nodeID), Text.equal)) {
            case (?node) {
                return ?node.wallet;
            };
            case (_) {
                return null;
            };
        };
    };

    private func getNodeType(_nodeID : Text) : ?Nat {
        if (Trie.get(computingNodes, text_key(_nodeID), Text.equal) != null) {
            return ?NodeComputing;
        };

        if (Trie.get(routerNodes, text_key(_nodeID), Text.equal) != null) {
            return ?NodeRouter;
        };

        if (Trie.get(validatorNodes, text_key(_nodeID), Text.equal) != null) {
            return ?NodeValidator;
        };

        return null;
    };

    // for routers and validators who do not need do pog,
    //here simulate the epower for them by percentage passed during the day.
    private func simulateEPower(day_percent : Nat) : Nat {
        10000 * dayValidationRounds * day_percent / 100;
    };

    public shared (msg) func updateDayValidaionRounds(rounds : Nat) : async emcResult {
        dayValidationRounds := rounds;
        return #Ok(0);
    };

    //return validated times and total computing power for current day
    public shared query (msg) func myCurrentEPower(_nodeID : Text) : async (Nat, Float) {
        var today = Time.now() / dayNanos;

        if (isValidatorNode(_nodeID) or isRouterNode(_nodeID)) {
            return (0, Float.fromInt(simulateEPower(Int.abs((Time.now() - today * dayNanos) * 100 / dayNanos))) / 10000);
        };

        switch (rewardPools.get(today)) {
            case (?rewardPool) {
                switch (rewardPool.get(_nodeID)) {
                    case (?record) {
                        return (record.validatedTimes, Float.fromInt(record.computingPower) / 10000);
                    };
                    case (_) {

                    };
                };
            };
            case (_) {};
        };
        return (0, 0);
    };

    //node validated
    private func nodeValidated(nv : NodeValidationUnit, day : Int, averagePower : Nat) {
        var wallet = getNodePrincipal(nv.nodeID);
        switch (wallet) {
            case (?p) {
                switch (rewardPools.get(day)) {
                    case (?rewardPool) {
                        switch (rewardPool.get(nv.nodeID)) {
                            case (?record) {
                                record.computingPower += averagePower;
                                record.validatedTimes += 1;
                            };
                            case (_) {
                                let rewardRecord : emcReward.RewardRecord = {
                                    nodeID = nv.nodeID;
                                    wallet = p;
                                    var computingPower = averagePower;
                                    var totalPower = 0;
                                    var validatedTimes = 1;
                                    var rewardAmount = 0;
                                    var rewardDay = day;
                                    var distributed = 0;
                                };
                                rewardPool.put(nv.nodeID, rewardRecord);
                            };
                        };
                    };
                    case (_) {
                        let rewardRecord : emcReward.RewardRecord = {
                            nodeID = nv.nodeID;
                            wallet = p;
                            var computingPower = averagePower;
                            var totalPower = 0;
                            var validatedTimes = 1;
                            var rewardAmount = 0;
                            var rewardDay = day;
                            var distributed = 0;
                        };

                        let rewardPool = HashMap.HashMap<Text, emcReward.RewardRecord>(1, Text.equal, Text.hash);
                        rewardPool.put(nv.nodeID, rewardRecord);
                        rewardPools.put(day, rewardPool);
                    };
                };
            };
            case (_) {
                return;
            };
        };

    };

    private func addNewNodeValidation(nv : NodeValidationUnit, day : Int, addNew : Bool) : Bool {
        let recordText = nv.nodeID # Principal.toText(nv.validator) # Nat.toText(nv.validationTicket);
        let nodeText = nv.nodeID # Nat.toText(nv.validationTicket);
        switch (validationPools.get(day)) {
            case (?nvPool) {
                switch (nvPool.get(nodeText)) {
                    case (?nodeValidations) {
                        switch (nodeValidations.get(recordText)) {
                            case (?record) {
                                //duplicated validation from same node & ticket & validator
                            };
                            case (_) {
                                //node validation by new validator
                                nodeValidations.put(recordText, nv);
                                if (nodeValidations.size() * 3 > Trie.size(validators) * 2) {
                                    if ((nodeValidations.size() -1) * 3 <= Trie.size(validators) * 2) {
                                        //node validation confirm here with average computing power
                                        //base on first comping x validations
                                        var averagePower : Nat = 0;
                                        for (val in nodeValidations.vals()) {
                                            averagePower += val.power;
                                        };
                                        averagePower /= nodeValidations.size();
                                        nodeValidated(nv, day, averagePower);
                                    } else {
                                        //ignore the later coming y validations
                                    };
                                };

                                return true;
                            };
                        };
                    };
                    case (null) {
                        if (addNew) {
                            let nodeValidations = HashMap.HashMap<Text, NodeValidationUnit>(1, Text.equal, Text.hash);
                            nodeValidations.put(recordText, nv);
                            nvPool.put(nodeText, nodeValidations);
                            return true;
                        };
                    };
                };
            };
            case (_) {
                if (addNew) {
                    let nodeValidations = HashMap.HashMap<Text, NodeValidationUnit>(1, Text.equal, Text.hash);
                    nodeValidations.put(recordText, nv);

                    let nvPool = HashMap.HashMap<Text, HashMap.HashMap<Text, NodeValidationUnit>>(1, Text.equal, Text.hash);
                    nvPool.put(nodeText, nodeValidations);
                    validationPools.put(day, nvPool);

                    return true;
                };
            };
        };
        return false;
    };

    public shared (msg) func submitComputingValidation(_validations : [NodeValidationRequest]) : async emcResult {
        if (isValidator(msg.caller) == false) {
            return #Err(#NotAValidator);
        };

        var confirmed : Nat = 0;
        var today = Time.now() / dayNanos;

        for (val in _validations.vals()) {
            if (isComputingNode(val.targetNodeID)) {
                // new validation unit
                let unit : NodeValidationUnit = {
                    nodeID = val.targetNodeID;
                    nodeType = NodeComputing;
                    validator = msg.caller;//use caller to avoid fake/wrong validator
                    validationTicket = val.validationTicket;
                    power = 15_000 * 10_000 / val.power; //X10_000 to avoid using float type
                    validationDay = today;
                };

                //check yestoday
                if (addNewNodeValidation(unit, today -1, false)) {
                    confirmed += 1;
                } else {
                    if (addNewNodeValidation(unit, today, true)) {
                        confirmed += 1;
                    } else {};
                };
            };

        };
        return #Ok(confirmed);
    };

    //emc management
    public shared (msg) func selfbalance() : async Nat {
        await tokenCanister.balanceOf(Principal.fromActor(self));
    };

    public shared (msg) func withdrawTo(account : Principal) : async Nat {
        assert (msg.caller == owner);
        let emcBalance = await tokenCanister.balanceOf(Principal.fromActor(self));
        var toWithdraw : Nat = 0;
        if (rewardPoolBalance + totalStaking <= emcBalance) {
            toWithdraw := rewardPoolBalance;
        } else {
            toWithdraw := emcBalance - totalStaking;
        };
        let res = await tokenCanister.transfer(account, toWithdraw);
        switch (res) {
            case (#Ok(txnID)) {
                rewardPoolBalance := 0;
                return toWithdraw;
            };
            case (#Err(#InsufficientBalance)) {
                return 0;
            };
            case (#Err(other)) {
                return 0;
            };
        };
    };

    public shared query (msg) func getOwner() : async Principal {
        owner;
    };

    public shared query (msg) func whoAmI() : async Principal {
        msg.caller;
    };

    public shared query (msg) func getCurrentDayReward() : async Nat {
        let age : Nat = Int.abs(Time.now() / dayNanos) - startDay;
        emcReward.getDayReward(age);
    };

    // ***temporary function will be deleted next update***
    // public shared (msg) func recalcStakingPower() : async emcResult {
    //     if (msg.caller != owner) {
    //         return #Err(#CallerNotAuthorized);
    //     };

    //     var fixes : Nat = 0;
    //     for (val in stakePool.vals()) {
    //         switch (computingNodes.get(val.nodeID)) {
    //             case (?node) {
    //                 switch (calcStakingPower(node.nodeType, val.stakeDays, val.stakeAmount)) {
    //                     case (#Ok(p)) {
    //                         if (val.stakingPower != p) {
    //                             fixes += 1;
    //                             val.stakingPower := p;
    //                         };
    //                     };
    //                     case (others) {};
    //                 };
    //             };
    //             case (_) {};
    //         };
    //     };
    //     return #Ok(fixes);
    // };

    //Staking power 10000 times than defined in white paper to avoid float type using.
    private func calcStakingPower(nodeType : Nat, days : Nat, stakeAmount : Nat) : emcResult {
        var power : Nat = 0;
        if (nodeType == NodeValidator) {
            if (days < 360) { return #Err(#StakeTooShort) };
            if (stakeAmount < 1_000_000 * emcDecimals) {
                return #Err(#StakeNotEnough);
            };
            power := stakeAmount * 100 * 10_000 / 1_000_000 / emcDecimals;
        } else if (nodeType == NodeRouter) {
            if (days < 180) { return #Err(#StakeTooShort) };
            if (stakeAmount < 100_000 * emcDecimals) {
                return #Err(#StakeNotEnough);
            };
            power := stakeAmount * 10 * 10_000 / 100_000 / emcDecimals;
        } else {
            //here should check min staking amount for computing node, TBD

            power := switch (days) {
                case 7 { 14_000 };
                case 30 { 27_000 };
                case 90 { 62_000 };
                case 180 { 100_000 };
                case other { 10_000 };
            };
        };
        return #Ok(power);
    };

    public shared (msg) func stake(emcAmount : Nat, days : Nat, _nodeID : Text) : async emcResult {
        switch (getNodeByID(_nodeID)) {
            case (?node) {
                var power : Nat = 0;
                switch (calcStakingPower(node.nodeType, days, emcAmount)) {
                    case (#Ok(p)) {
                        power := p;
                    };
                    case (others) {
                        return others;
                    };
                };
                switch (Trie.find(stakePool, text_key(_nodeID), Text.equal)) {
                    case (?stakeRecord) {
                        return #Err(#StakedBefore);
                    };
                    case (_) {
                        let result = await tokenCanister.transferFrom(msg.caller, Principal.fromActor(self), emcAmount);
                        switch (result) {
                            case (#Ok(amount)) {
                                let stakeRecord : emcReward.StakeRecord = {
                                    staker = msg.caller;
                                    stakeAmount = emcAmount;
                                    stakeDays = days;
                                    stakeTime = Time.now();
                                    var balance = emcAmount;
                                    nodeWallet = node.wallet;
                                    nodeID = _nodeID;
                                    var stakingPower = power;
                                };
                                stakePool := Trie.put(stakePool, text_key(_nodeID), Text.equal, stakeRecord).0;
                                totalStaking += emcAmount;
                                return #Ok(amount);
                            };
                            case (#Err(others)) {
                                return #Err(#TokenTransferFailed);
                            };
                        };

                    };
                };

            };
            case (_) {
                return #Err(#NodeNotExist);
            };
        };
    };

    public shared (msg) func unStake(_nodeID : Text) : async emcResult {
        switch (Trie.find(stakePool, text_key(_nodeID), Text.equal)) {
            case (?stakeRecord) {
                if (stakeRecord.staker == msg.caller) {
                    if (testnetRunning and stakeRecord.stakeTime + stakeRecord.stakeDays * dayNanos < Time.now()) {
                        return #Err(#CanNotUnstake);
                    };

                    let result = await tokenCanister.transfer(msg.caller, stakeRecord.stakeAmount);
                    switch (result) {
                        case (#Ok(amount)) {
                            stakeRecord.balance := 0;
                            stakeRecord.stakingPower := 10000;
                            totalStaking -= stakeRecord.stakeAmount;
                            stakePool := Trie.remove(stakePool, text_key(_nodeID), Text.equal).0;
                            return #Ok(stakeRecord.stakeAmount);
                        };
                        case (others) {
                            return #Err(#TokenTransferFailed);
                        };
                    };
                } else {
                    return #Err(#NoStakeFound);
                };
            };
            case (_) {
                return #Err(#NoStakeFound);
            };
        };
    };

    public shared query (msg) func myStake(_nodeID : Text) : async (Nat, Nat, Nat) {
        switch (Trie.find(stakePool, text_key(_nodeID), Text.equal)) {
            case (?stake) {
                return (stake.stakeAmount, stake.stakeDays, stake.stakingPower);
            };
            case (_) {};
        };
        (0, 0, 10000);
    };

    private func getStakePower(_nodeID : Text) : Nat {
        switch (Trie.find(stakePool, text_key(_nodeID), Text.equal)) {
            case (?record) {
                record.stakingPower;
            };
            case (_) {
                switch (getNodeType(_nodeID)) {
                    case (?nodetype) {
                        if (nodetype == NodeRouter or nodetype == NodeValidator) {
                            0;
                        } else {
                            10000;
                        };
                    };
                    case (_) {
                        0;
                    };
                };
            };
        };
    };

    private func updateRewardStatus(_nodeID : Text, _wallet : Principal, newReward : Nat, newDistribution : Nat) : () {
        switch (Trie.find(rewardStatus, text_key(_nodeID), Text.equal)) {
            case (?record) {
                record.totalReward += newReward;
                record.distributed += newDistribution;
            };
            case (_) {
                var record : emcReward.RewardStatus = {
                    nodeID = _nodeID;
                    wallet = _wallet;
                    var totalReward = newReward;
                    var distributed = newDistribution;
                };
                rewardStatus := Trie.put(rewardStatus, text_key(_nodeID), Text.equal, record).0;
            };
        };
        totalReward += newReward;
        totalDistributed += newDistribution;
    };

    public shared query (msg) func showNodeRewardStatus(_nodeID : Text) : async (Text, Nat, Nat) {
        switch (Trie.find(rewardStatus, text_key(_nodeID), Text.equal)) {
            case (?record) {
                return (_nodeID, record.totalReward, record.distributed);
            };
            case (_) {
                return (_nodeID, 0, 0);
            };
        };
    };

    // return balance of reward pool, total staking amount, total caculated reward, total distributed reward.
    public shared query (msg) func showTotalRewardsStatus() : async (Nat, Nat, Nat, Nat) {
        (rewardPoolBalance, totalStaking, totalReward, totalDistributed);
    };

    // return count of router nodes, validator nodes, computing nodes and pog succeed nodes;
    public shared query (msg) func getNodeStatus() : async (Nat, Nat, Nat, Nat) {
        var pogCount : Nat = 0;
        let today : Nat = Int.abs(Time.now() / dayNanos);
        switch (rewardPools.get(today)) {
            case (?rewardPool) {
                pogCount := rewardPool.size();
            };
            case (_) {
                pogCount := 0;
            };
        };

        return (Trie.size(routerNodes), Trie.size(validatorNodes), Trie.size(computingNodes), pogCount);
    };

    public shared (msg) func postDeposit() : async (Nat) {
        assert (msg.caller == owner);
        let emcBalance = await tokenCanister.balanceOf(Principal.fromActor(self));
        rewardPoolBalance := emcBalance - totalStaking;
        return rewardPoolBalance;
    };

    public shared query (msg) func showFaildReward(start : Nat, length : Nat) : async [emcReward.FailedReward] {
        let array = Trie.toArray<Text, emcReward.FailedReward, emcReward.FailedReward>(
            failedRewardPool,
            func(k, v) = v,
        );

        if (start >= Array.size(array)) {
            return [];
        } else if (start + length > Array.size(array)) {
            return Array.subArray(array, start, Array.size(array) - start);
        } else {
            return Array.subArray(array, start, length);
        };
    };

    private func distributeReward() : async () {
        let today : Nat = Int.abs(Time.now() / dayNanos);

        //distribute rewards for yestoday
        let targetDay = today - 1;
        let dayReward = emcReward.getDayReward(targetDay -startDay);
        switch (rewardPools.get(targetDay)) {
            case (?rewardRecords) {
                var totalPower : Nat = 0;
                for (val in rewardRecords.vals()) {
                    val.totalPower := val.computingPower * getStakePower(val.nodeID);
                    totalPower += val.totalPower;
                };

                //whole day EPower
                var simulatedEPower = simulateEPower(100);

                //addup routers
                let router_iter = Trie.iter(routerNodes);
                for ((k, v) in router_iter) {
                    let rewardRecord : emcReward.RewardRecord = {
                        nodeID = v.nodeID;
                        wallet = v.wallet;
                        var computingPower = simulatedEPower;
                        var totalPower = simulatedEPower * getStakePower(v.nodeID);
                        var validatedTimes = 0;
                        var rewardAmount = 0;
                        var rewardDay = targetDay;
                        var distributed = 0;
                    };
                    rewardRecords.put(v.nodeID, rewardRecord);

                    totalPower += rewardRecord.totalPower;
                };

                //addup validators
                let validator_iter = Trie.iter(validatorNodes);
                for ((k, v) in validator_iter) {
                    let rewardRecord : emcReward.RewardRecord = {
                        nodeID = v.nodeID;
                        wallet = v.wallet;
                        var computingPower = simulatedEPower;
                        var totalPower = simulatedEPower * getStakePower(v.nodeID);
                        var validatedTimes = 0;
                        var rewardAmount = 0;
                        var rewardDay = targetDay;
                        var distributed = 0;
                    };
                    rewardRecords.put(v.nodeID, rewardRecord);

                    totalPower += rewardRecord.totalPower;
                };

                //send reward to computing ndoes
                for (val in rewardRecords.vals()) {
                    val.rewardAmount := dayReward * val.totalPower / totalPower;
                    updateRewardStatus(val.nodeID, val.wallet, val.rewardAmount, 0); //update reward
                    let result = await tokenCanister.transfer(val.wallet, val.rewardAmount);
                    switch (result) {
                        case (#Ok(amount)) {
                            rewardPoolBalance -= val.rewardAmount;
                            val.distributed := Time.now();
                            updateRewardStatus(val.nodeID, val.wallet, 0, val.rewardAmount); //update distribution
                        };
                        case (others) {
                            val.distributed := 0;
                            var key = val.nodeID # "-" # Nat.toText(targetDay);

                            failedRewardPool := Trie.put(
                                failedRewardPool,
                                text_key(key),
                                Text.equal,
                                {
                                    nodeID = val.nodeID;
                                    wallet = val.wallet;
                                    computingPower = val.computingPower;
                                    validatedTimes = val.validatedTimes;
                                    rewardAmount = val.rewardAmount;
                                    totalPower = val.totalPower;
                                    rewardDay = val.rewardDay;
                                    dayPower = totalPower;
                                    faildTime = Time.now();
                                },
                            ).0;
                        };
                    };
                };

                //release data for targetday
                rewardPools.delete(targetDay);
                validationPools.delete(targetDay);
            };
            case (_) {
                //nothing to do
            };
        };
    };

    public shared query (msg) func tryTodayReward() : async [(Text, Nat)] {
        //try rewards for today
        let targetDay = Int.abs(Time.now() / dayNanos);
        let dayReward = emcReward.getDayReward(targetDay -startDay);
        var currentRD = HashMap.HashMap<Text, Nat>(1, Text.equal, Text.hash);
        switch (rewardPools.get(targetDay)) {
            case (?rewardRecords) {
                var totalPower : Nat = 0;
                var simulatedEPower = simulateEPower(Int.abs((Time.now() - targetDay * dayNanos) * 100 / dayNanos));

                for (val in rewardRecords.vals()) {
                    totalPower += val.computingPower * getStakePower(val.nodeID);
                };
                //addup routers
                let router_iter = Trie.iter(routerNodes);
                for ((k, v) in router_iter) {
                    totalPower += simulatedEPower * getStakePower(v.nodeID);
                };

                //addup validators
                let validator_iter = Trie.iter(validatorNodes);
                for ((k, v) in validator_iter) {
                    totalPower += simulatedEPower * getStakePower(v.nodeID);
                };

                for (val in rewardRecords.vals()) {
                    currentRD.put(val.nodeID, dayReward * (val.computingPower * getStakePower(val.nodeID)) / totalPower);
                };
                for ((k, v) in router_iter) {
                    currentRD.put(v.nodeID, dayReward * simulatedEPower * getStakePower(v.nodeID) / totalPower);
                };
                for ((k, v) in validator_iter) {
                    currentRD.put(v.nodeID, dayReward * simulatedEPower * getStakePower(v.nodeID) / totalPower);
                };
            };
            case (_) {
                //nothing to do
            };
        };
        return Iter.toArray(currentRD.entries());
    };

    public shared (msg) func exeuteReward() : async emcResult {
        assert (msg.caller == owner);
        await distributeReward();
        return #Ok(0);
    };

    public shared (msg) func launchRewardTask() : async emcResult {
        assert (msg.caller == owner);

        ignore Timer.setTimer(
            #seconds(daySeconds - Int.abs(Time.now() / 1_000_000_000) % daySeconds + hourSeconds),
            func() : async () {
                timerID := Timer.recurringTimer(#seconds daySeconds, distributeReward);
                await distributeReward();
            },
        );

        return #Ok(0);
    };

    public shared (msg) func cancelRewardTask() : async emcResult {
        assert (msg.caller == owner);
        Timer.cancelTimer(timerID);
        return #Ok(0);
    };

    /*
    * upgrade functions
    */

    //changed to use stable vars, next upgrade won't need these
    system func preupgrade() {
        // nodeEntries := Iter.toArray(nodePool.entries());
        // validatorEntries := Iter.toArray(validators.entries());

        // rewardStatusEntries := Iter.toArray(rewardStatus.entries());
        // failedRewardEntries := Iter.toArray(failedRewardPool.entries());
        // stakePoolEntires := Iter.toArray(stakePool.entries());
    };

    // changed to use stable vars, should only be executed one time, delete them all after upgrade
    system func postupgrade() {
        for((k, v) in nodeEntries.vals()){
            if(v.nodeType == NodeRouter){
                routerNodes := Trie.put(routerNodes, text_key(k), Text.equal, v).0;
            }else if(v.nodeType == NodeValidator){
                validatorNodes := Trie.put(validatorNodes, text_key(k), Text.equal, v).0;
            }else if(v.nodeType == NodeComputing){
                computingNodes := Trie.put(computingNodes, text_key(k), Text.equal, v).0;
            }
        };
        nodeEntries := [];

        for((k, v) in validatorEntries.vals()){
            validators := Trie.put(validators, account_key(k), Principal.equal, v).0;
        };
        validatorEntries := [];

        for((k, v) in rewardStatusEntries.vals()){
            rewardStatus := Trie.put(rewardStatus, text_key(k), Text.equal, v).0;
        };
        rewardStatusEntries := [];

        for((k, v) in stakePoolEntires.vals()){
            stakePool := Trie.put(stakePool, text_key(k), Text.equal, v).0;
        };
        stakePoolEntires := [];

        for((k, v) in failedRewardEntries.vals()){
            failedRewardPool := Trie.put(failedRewardPool, text_key(k), Text.equal, v).0;
        };
        failedRewardEntries := [];
    };
};
