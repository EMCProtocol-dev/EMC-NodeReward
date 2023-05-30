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
            #NoStakeFound;
            #CanNotUnstake;
        };
    };

    private var dayNanos : Nat = 1_000_000_000 * 3600 * 24;
    private var secNanos : Nat = 1_000_000_000;
    private var daySeconds : Nat = 3600 * 24;
    private var hourSeconds : Nat = 3600;
    private var owner : Principal = msg.caller;

    private stable var testnetRunning : Bool = true;
    private stable var rewardBalance : Nat = 30_000_000_000_000_000;
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

    private stable var routerNodeEntries : [(Text, Node)] = [];
    private stable var validatorNodeEntries : [(Text, Node)] = [];
    private stable var computingNodeEntries : [(Text, Node)] = [];
    private stable var validatorEntries : [(Principal, Time.Time)] = [];
    private stable var validationPoolEntries : [(Int, [(Text, [(Text, NodeValidationUnit)])])] = [];

    private var routerNodes = HashMap.HashMap<Text, Node>(1, Text.equal, Text.hash);
    private var validatorNodes = HashMap.HashMap<Text, Node>(1, Text.equal, Text.hash);
    private var computingNodes = HashMap.HashMap<Text, Node>(1, Text.equal, Text.hash);
    private var validators = HashMap.HashMap<Principal, Time.Time>(1, Principal.equal, Principal.hash);
    private var validationPools = TrieMap.TrieMap<Int, NodeValidationPool>(Int.equal, Int.hash);

    //node staking
    private var tokenCanister : emc_token_dip20.Token = actor (token);
    private stable var stakePoolEntires : [(Principal, emcReward.StakeRecord)] = [];
    private var stakePool = HashMap.HashMap<Principal, emcReward.StakeRecord>(1, Principal.equal, Principal.hash);

    //reward definations
    type NodeRewardRecordPool = HashMap.HashMap<Principal, emcReward.RewardRecord>;

    private var timerID : Nat = 0;
    private stable var startDay : Nat = Int.abs(Time.now() / dayNanos);

    private stable var rewardPoolsEntries : [(Int, [(Principal, emcReward.RewardRecord)])] = [];
    private stable var rewardStatusEntries : [(Principal, emcReward.RewardStatus)] = [];

    private var rewardPools = TrieMap.TrieMap<Int, NodeRewardRecordPool>(Int.equal, Int.hash);
    private var rewardStatus = HashMap.HashMap<Principal, emcReward.RewardStatus>(1, Principal.equal, Principal.hash);

    public shared (msg) func stopTestnet(stop : Bool) : async emcResult {
        assert (msg.caller == owner);
        testnetRunning := not stop;
        return #Ok(0);
    };

    public shared (msg) func addValidator(_validator : Principal) : async emcResult {
        // if (msg.caller != owner) {
        //     return #Err(#CallerNotAuthorized);
        // };

        if (validators.get(_validator) != null) {
            return #Err(#NodeAlreadyExist);
        };

        validators.put(_validator, Time.now());

        return #Ok(0);

    };

    public shared (msg) func removeValidator(_validator : Principal) : async emcResult {
        // if (msg.caller != owner) {
        //     return #Err(#CallerNotAuthorized);
        // };
        validators.delete(_validator);

        return #Ok(0);

    };

    //validators
    public shared query (msg) func listValidators() : async [(Principal, Time.Time)] {
        Iter.toArray(validators.entries());
    };

    public query func isValidator(who : Principal) : async Bool {
        return validators.get(who) != null;
    };

    //node management
    public shared (msg) func registerNode(_nodetype : NodeType, _nodeID : Text, _wallet : Principal) : async emcResult {
        let tmp : Node = {
            nodeType = _nodetype;
            nodeID = _nodeID;
            owner = msg.caller;
            wallet = _wallet;
            nodeStatus = #Alive;
            registered = Time.now();
            lastActiveTime = Time.now();
        };

        if (_nodetype == NodeRouter) {
            if (routerNodes.get(_nodeID) != null) {
                return #Err(#NodeAlreadyExist);
            };
            routerNodes.put(_nodeID, tmp);
            return #Ok(0);
        } else if (_nodetype == NodeValidator) {
            if (validators.get(msg.caller) == null) {
                return #Err(#NotAValidator);
            };

            if (validatorNodes.get(_nodeID) != null) {
                return #Err(#NodeAlreadyExist);
            };
            validatorNodes.put(_nodeID, tmp);
            return #Ok(0);
        } else if (_nodetype == NodeComputing) {
            if (computingNodes.get(_nodeID) != null) {
                return #Err(#NodeAlreadyExist);
            };
            computingNodes.put(_nodeID, tmp);
            return #Ok(0);
        } else {
            return #Err(#UnknowType);
        };
    };

    private func unregisterRouterNode(caller : Principal, nodeID : Text) {
        switch (routerNodes.get(nodeID)) {
            case (?node) {
                if (node.wallet == caller) {
                    routerNodes.delete(nodeID);
                };
            };
            case (_) {};
        };
    };

    private func unregisterValidatorNode(caller : Principal, nodeID : Text) {
        switch (validatorNodes.get(nodeID)) {
            case (?node) {
                if (node.wallet == caller) {
                    routerNodes.delete(nodeID);
                };
            };
            case (_) {};
        };
    };

    private func unregisterComputingNode(caller : Principal, nodeID : Text) {
        switch (computingNodes.get(nodeID)) {
            case (?node) {
                if (node.wallet == caller) {
                    routerNodes.delete(nodeID);
                };
            };
            case (_) {};
        };
    };

    public shared query (msg) func myNode(nodeID : Text) : async [(Principal, Nat)] {
        var node : ?Node = null;
        if (routerNodes.get(nodeID) != null) {
            node := routerNodes.get(nodeID);
        } else if (validatorNodes.get(nodeID) != null) {
            node := validatorNodes.get(nodeID);
        } else if (computingNodes.get(nodeID) != null) {
            node := computingNodes.get(nodeID);
        };

        switch (node) {
            case (?n) {
                return [(n.wallet,n.nodeType)];
            };
            case (_) {
                return [];
            };
        };
    };

    public shared (msg) func unregisterNode(nodetype : Nat, nodeID : Text) : async emcResult {
        if (nodetype == NodeRouter) {
            unregisterRouterNode(msg.caller, nodeID);
        } else if (nodetype == NodeValidator) {
            unregisterValidatorNode(msg.caller, nodeID);
        } else if (nodetype == NodeComputing) {
            unregisterComputingNode(msg.caller, nodeID);
        } else {
            return #Err(#UnknowType);
        };
        return #Ok(0);
    };

    public query func listNodes(nodeType : NodeType, start : Nat, limit : Nat) : async [(Text, Node)] {
        var nodes : [(Text, Node)] = [];
        if (nodeType == NodeRouter) {
            nodes := Iter.toArray(routerNodes.entries());
        } else if (nodeType == NodeValidator) {
            nodes := Iter.toArray(validatorNodes.entries());
        } else if (nodeType == NodeComputing) {
            nodes := Iter.toArray(computingNodes.entries());
        } else {
            return [];
        };

        assert (start <= nodes.size());
        if (start + limit > nodes.size()) {
            return Array.subArray<(Text, Node)>(nodes, start, nodes.size() -start);
        } else {
            return Array.subArray<(Text, Node)>(nodes, start, limit);
        };
    };

    public query func listComputingNodes(start : Nat, limit : Nat) : async [(Text, Node)] {
        let nodes = Iter.toArray(computingNodes.entries());
        assert (start <= nodes.size());
        if (start + limit > nodes.size()) {
            return Array.subArray<(Text, Node)>(nodes, start, nodes.size() -start);
        } else {
            return Array.subArray<(Text, Node)>(nodes, start, limit);
        };
    };

    private func getNodePrincipal(nodeID : Text, nodeType : NodeType) : ?Principal {
        var node : ?Node = null;
        if (nodeType == NodeRouter) {
            node := routerNodes.get(nodeID);
        } else if (nodeType == NodeValidator) {
            node := validatorNodes.get(nodeID);
        } else if (nodeType == NodeComputing) {
            node := computingNodes.get(nodeID);
        };

        switch (node) {
            case (?n) {
                return ?n.wallet;
            };
            case (_) {
                return null;
            };
        };
    };

    //node validated
    private func nodeValidated(nv : NodeValidationUnit, day : Int, count : Nat) {
        var principal = getNodePrincipal(nv.nodeID, nv.nodeType);
        switch (principal) {
            case (?p) {
                switch (rewardPools.get(day)) {
                    case (?rewardPool) {
                        switch (rewardPool.get(p)) {
                            case (?record) {
                                if (nv.nodeType == NodeComputing) {
                                    record.computingPower := (record.computingPower * (count -1) + nv.power) / count;
                                } else {
                                    record.computingPower := 10000; //for validator and router, power set to 1(*10000)
                                };
                            };
                            case (_) {
                                let rewardRecord : emcReward.RewardRecord = {
                                    account = p;
                                    var computingPower = 0;
                                    var stakingPower = 1;
                                    var totalPower = 1;
                                    var rewardAmount = 0;
                                    var rewardDay = day;
                                    var distributed = 0;
                                };
                                rewardPool.put(p, rewardRecord);
                            };
                        };
                    };
                    case (_) {
                        let rewardRecord : emcReward.RewardRecord = {
                            account = p;
                            var computingPower = 0;
                            var stakingPower = 1;
                            var totalPower = 1;
                            var rewardAmount = 0;
                            var rewardDay = day;
                            var distributed = 0;
                        };
                        let rewardPool = HashMap.HashMap<Principal, emcReward.RewardRecord>(1, Principal.equal, Principal.hash);
                        rewardPool.put(p, rewardRecord);
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
                                if (nodeValidations.size() * 3 > validators.size() * 2) {
                                    //node validation confirm here
                                    nodeValidated(nv, day, nodeValidations.size());
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

    public shared (msg) func submitValidation(_validations : [NodeValidationRequest]) : async emcResult {
        if (validators.get(msg.caller) == null) {
            return #Err(#NotAValidator);
        };

        var confirmed : Nat = 0;
        var today = Time.now() / dayNanos;

        for (val in _validations.vals()) {
            // new validation unit
            let unit : NodeValidationUnit = {
                nodeID = val.targetNodeID;
                nodeType = val.nodeType;
                validator = val.validator;
                validationTicket = val.validationTicket;
                power = 15000 * 10000 / val.power; //X10000 to avoid using float type
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
        if (rewardBalance + totalStaking <= emcBalance) {
            toWithdraw := rewardBalance;
        } else {
            toWithdraw := emcBalance - totalStaking;
        };
        let res = await tokenCanister.transfer(account, toWithdraw);
        switch (res) {
            case (#Ok(txnID)) {
                rewardBalance := 0;
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

    //reward management
    // public shared (msg) func setTestDays(days:Nat): async emcResult {
    //     assert(msg.caller == owner);
    //     emcReward.setTestDays(days);
    // };

    public shared query (msg) func getCurrentDayReward() : async Nat {
        let age : Nat = Int.abs(Time.now() / dayNanos) - startDay;
        emcReward.getDayReward(age);
    };

    public shared (msg) func stake(emcAmount : Nat, days : Nat, nodeID : Text, owner : Principal) : async emcResult {
        var power : Nat = (
            if (validatorNodes.get(nodeID) != null) {
                if (days < 360) { return #Err(#StakeTooShort) };
                10000000;
            } else if (routerNodes.get(nodeID) != null) {
                if (days < 180) { return #Err(#StakeTooShort) };
                100000;
            } else if (computingNodes.get(nodeID) != null) {
                switch (days) {
                    case 7 { 14000 };
                    case 30 { 27000 };
                    case 90 { 62000 };
                    case 180 { 100000 };
                    case other { 10000 };
                };
            } else {
                return #Err(#NodeNotExist);
            }
        );

        switch (stakePool.get(owner)) {
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
                            nodeOwner = owner;
                            nodeID = nodeID;
                            var stakingPower = power;
                        };
                        stakePool.put(owner, stakeRecord);
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

    public shared (msg) func unstake(nodeOwner : Principal) : async emcResult {
        switch (stakePool.get(nodeOwner)) {
            case (?stakeRecord) {
                if (stakeRecord.staker == msg.caller) {
                    if (testnetRunning and stakeRecord.stakeTime + stakeRecord.stakeDays * dayNanos < Time.now()) {
                        return #Err(#CanNotUnstake);
                    };

                    let result = await tokenCanister.transfer(msg.caller, stakeRecord.stakeAmount);
                    switch (result) {
                        case (#Ok(amount)) {
                            stakeRecord.balance := 0;
                            stakeRecord.stakingPower := 1;
                            totalStaking -= stakeRecord.stakeAmount;
                            stakePool.delete(nodeOwner);
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

    public shared query (msg) func myStake(nodeOwner : Principal) : async (Nat, Nat, Nat) {
        let stake = stakePool.get(nodeOwner);
        switch (stake) {
            case (?stake) {
                return (stake.stakeAmount, stake.stakeDays, stake.stakingPower);
            };
            case (_) {
                return (0, 0, 10000);
            };
        };
    };

    private func getStakePower(nodeOwner : Principal) : Nat {
        switch (stakePool.get(nodeOwner)) {
            case (?record) {
                record.stakingPower;
            };
            case (_) {
                10000;
            };
        };
    };

    private func updateRewardStatus(_account : Principal, newReward : Nat, newDistribution : Nat) : () {
        switch (rewardStatus.get(_account)) {
            case (?record) {
                record.totalReward += newReward;
                record.distributed += newDistribution;
            };
            case (_) {
                var record : emcReward.RewardStatus = {
                    account = _account;
                    var totalReward = newReward;
                    var distributed = newDistribution;
                };
                rewardStatus.put(_account, record);
            };
        };
        totalReward += newReward;
        totalDistributed += newDistribution;
    };

    public shared query (msg) func showRewardStatus(account : Principal) : async (Principal, Nat, Nat) {
        switch (rewardStatus.get(account)) {
            case (?record) {
                return (account, record.totalReward, record.distributed);
            };
            case (_) {
                return (account, 0, 0);
            };
        };
    };

    private func distributeReward() : async () {
        let today : Nat = Int.abs(Time.now() / dayNanos);

        //distribute rewards for yestoday
        let targetDay = today - 1;
        let dayReward = emcReward.getDayReward(targetDay);
        switch (rewardPools.get(targetDay)) {
            case (?rewardRecords) {
                var totalPower : Nat = 0;
                for (val in rewardRecords.vals()) {
                    val.totalPower := val.computingPower * getStakePower(val.account);
                    totalPower += val.totalPower;
                };
                for (val in rewardRecords.vals()) {
                    val.rewardAmount := dayReward * val.totalPower / totalPower;
                    updateRewardStatus(val.account, val.rewardAmount, 0); //update reward
                    let result = await tokenCanister.transferFrom(Principal.fromActor(self), val.account, val.rewardAmount);
                    switch (result) {
                        case (#Ok(amount)) {
                            rewardBalance -= val.rewardAmount;
                            val.distributed := Time.now();
                            updateRewardStatus(val.account, 0, val.rewardAmount); //update distribution
                        };
                        case (others) {
                            val.distributed := 0;
                        };
                    };
                };
                rewardPools.delete(targetDay);
            };
            case (_) {
                //nothing to do
            };
        };
    };

    public shared (msg) func exeuteReward(dayAjust : Nat) : async emcResult {
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
    system func preupgrade() {
        routerNodeEntries := Iter.toArray(routerNodes.entries());
        validatorNodeEntries := Iter.toArray(validatorNodes.entries());
        computingNodeEntries := Iter.toArray(computingNodes.entries());
        validatorEntries := Iter.toArray(validators.entries());

        rewardStatusEntries := Iter.toArray(rewardStatus.entries());
        stakePoolEntires := Iter.toArray(stakePool.entries());
    };

    system func postupgrade() {
        routerNodes := HashMap.fromIter<Text, Node>(routerNodeEntries.vals(), 1, Text.equal, Text.hash);
        routerNodeEntries := [];
        validatorNodes := HashMap.fromIter<Text, Node>(validatorNodeEntries.vals(), 1, Text.equal, Text.hash);
        validatorNodeEntries := [];
        computingNodes := HashMap.fromIter<Text, Node>(computingNodeEntries.vals(), 1, Text.equal, Text.hash);
        computingNodeEntries := [];
        validators := HashMap.fromIter<Principal, Time.Time>(validatorEntries.vals(), 1, Principal.equal, Principal.hash);
        validatorEntries := [];

        rewardStatus := HashMap.fromIter<Principal, emcReward.RewardStatus>(rewardStatusEntries.vals(), 1, Principal.equal, Principal.hash);
        stakePool := HashMap.fromIter<Principal, emcReward.StakeRecord>(stakePoolEntires.vals(), 1, Principal.equal, Principal.hash);
    };
};
