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
    private var owner : Principal = msg.caller;

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

    private stable var nodeEntries : [(Text, Node)] = [];
    private stable var validatorEntries : [(Principal, Time.Time)] = [];
    private stable var validationPoolEntries : [(Int, [(Text, [(Text, NodeValidationUnit)])])] = [];

    private var nodePool = HashMap.HashMap<Text, Node>(1, Text.equal, Text.hash);
    private var validators = HashMap.HashMap<Principal, Time.Time>(1, Principal.equal, Principal.hash);
    private var validationPools = TrieMap.TrieMap<Int, NodeValidationPool>(Int.equal, Int.hash);

    //node staking
    private var tokenCanister : emc_token_dip20.Token = actor (token);
    private stable var stakePoolEntires : [(Text, emcReward.StakeRecord)] = [];
    private var stakePool = HashMap.HashMap<Text, emcReward.StakeRecord>(1, Text.equal, Text.hash);

    //reward definations
    type NodeRewardRecordPool = HashMap.HashMap<Text, emcReward.RewardRecord>;

    private var timerID : Nat = 0;
    private stable var startDay : Nat = Int.abs(Time.now() / dayNanos);

    private stable var rewardPoolsEntries : [(Int, [(Principal, emcReward.RewardRecord)])] = [];
    private stable var failedRewardEntries : [(Text, emcReward.FailedReward)] = [];
    private stable var rewardStatusEntries : [(Text, emcReward.RewardStatus)] = [];

    private var rewardPools = TrieMap.TrieMap<Int, NodeRewardRecordPool>(Int.equal, Int.hash);
    private var failedRewardPool = HashMap.HashMap<Text, emcReward.FailedReward>(1, Text.equal, Text.hash);
    private var rewardStatus = HashMap.HashMap<Text, emcReward.RewardStatus>(1, Text.equal, Text.hash);

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

    public shared (msg) func addValidator(_validator : Principal) : async emcResult {
        if (msg.caller != owner) {
            return #Err(#CallerNotAuthorized);
        };

        if (validators.get(_validator) != null) {
            return #Err(#NodeAlreadyExist);
        };

        validators.put(_validator, Time.now());

        return #Ok(0);

    };

    public shared (msg) func removeValidator(_validator : Principal) : async emcResult {
        if (msg.caller != owner) {
            return #Err(#CallerNotAuthorized);
        };

        validators.delete(_validator);

        return #Ok(0);

    };

    //validators
    public shared query (msg) func listValidators() : async [(Principal, Time.Time)] {
        Iter.toArray(validators.entries());
    };

    //validator nodes
    public shared query (msg) func listValidatorNodes() : async [(Text, Node)] {
        var validatorNodes = HashMap.HashMap<Text, Node>(1, Text.equal, Text.hash);
        for (val in nodePool.vals()) {
            if (val.nodeType == NodeValidator) {
                validatorNodes.put(val.nodeID, val);
            };
        };
        return Iter.toArray(validatorNodes.entries());
    };

    public query func isValidator(who : Principal) : async Bool {
        return validators.get(who) != null;
    };

    //node management
    public shared (msg) func registerNode(_nodetype : NodeType, _nodeID : Text, _wallet : Principal) : async emcResult {
        switch (nodePool.get(_nodeID)) {
            case (?node) {
                return #Err(#NodeAlreadyExist);
            };
            case (_) {
                if (_nodetype == NodeValidator) {
                    if (validators.get(msg.caller) == null) {
                        return #Err(#NotAValidator);
                    };
                };

                if (
                    _nodetype != NodeValidator and _nodetype != NodeRouter and _nodetype != NodeComputing
                ) {
                    return #Err(#UnknowType);
                };

                let tmp : Node = {
                    nodeType = _nodetype;
                    nodeID = _nodeID;
                    owner = msg.caller;
                    wallet = _wallet;
                    registered = Time.now();
                };
                nodePool.put(_nodeID, tmp);
                return #Ok(0);
            };
        };
    };

    public shared (msg) func unregisterNode(nodeID : Text) : async emcResult {
        switch (nodePool.get(nodeID)) {
            case (?node) {
                if (node.owner == msg.caller) {
                    nodePool.delete(nodeID);
                    return #Ok(0);
                } else {
                    return #Err(#CallerNotAuthorized);
                };
            };
            case (_) {};
        };
        return #Err(#NodeNotExist);
    };

    public shared query (msg) func myNode(nodeID : Text) : async [Node] {
        switch (nodePool.get(nodeID)) {
            case (?node) {
                return [node];
            };
            case (_) {
                return [];
            };
        };
    };

    public query func listNodes(nodeType : Nat, start : Nat, limit : Nat) : async [(Text, Node)] {
        var nodes = HashMap.HashMap<Text, Node>(1, Text.equal, Text.hash);
        for (val in nodePool.vals()) {
            if (val.nodeType == nodeType) {
                nodes.put(val.nodeID, val);
            };
        };

        var nodearray = Iter.toArray(nodes.entries());

        assert (start <= nodes.size());
        if (start + limit > nodes.size()) {
            return Array.subArray<(Text, Node)>(nodearray, start, nodes.size() -start);
        } else {
            return Array.subArray<(Text, Node)>(nodearray, start, limit);
        };
    };

    private func getNodePrincipal(nodeID : Text) : ?Principal {
        switch (nodePool.get(nodeID)) {
            case (?n) {
                return ?n.wallet;
            };
            case (_) {
                return null;
            };
        };
    };

    private func getNodeType(nodeID : Text) : ?Nat {
        switch (nodePool.get(nodeID)) {
            case (?n) {
                return ?n.nodeType;
            };
            case (_) {
                return null;
            };
        };
    };

    //return validated times and total computing power for current day
    public shared query (msg) func myCurrentEPower(nodeID : Text) : async (Nat, Float) {
        var today = Time.now() / dayNanos;
        switch (rewardPools.get(today)) {
            case (?rewardPool) {
                switch (rewardPool.get(nodeID)) {
                    case (?record) {
                        return (record.validatedTimes, Float.fromInt(record.computingPower) / 10000);
                    };
                    case (_) {};
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
                                if (nv.nodeType == NodeValidator) {
                                    record.computingPower += 10_000; //for validator power set to 1
                                } else {
                                    record.computingPower += averagePower;
                                };
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
                                if (nv.nodeType == NodeValidator) {
                                    rewardRecord.computingPower := 10_000; //for validator power set to 1
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

                        if (nv.nodeType == NodeValidator) {
                            rewardRecord.computingPower := 10_000; //for validator power set to 1
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
                                if (nodeValidations.size() * 3 > validators.size() * 2) {
                                    if ((nodeValidations.size() -1) * 3 <= validators.size() * 2) {
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

    public shared (msg) func submitValidation(_validations : [NodeValidationRequest]) : async emcResult {
        if (validators.get(msg.caller) == null) {
            return #Err(#NotAValidator);
        };

        var confirmed : Nat = 0;
        var today = Time.now() / dayNanos;

        for (val in _validations.vals()) {
            switch (getNodeType(val.targetNodeID)) {
                case (?nodetype) {
                    // new validation unit
                    let unit : NodeValidationUnit = {
                        nodeID = val.targetNodeID;
                        nodeType = nodetype;
                        validator = val.validator;
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
                case (_) {

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

    public shared (msg) func recalcStakingPower() : async emcResult {
        if (msg.caller != owner) {
            return #Err(#CallerNotAuthorized);
        };

        var fixes : Nat = 0;
        for (val in stakePool.vals()) {
            switch (nodePool.get(val.nodeID)) {
                case (?node) {
                    switch (calcStakingPower(node.nodeType, val.stakeDays, val.stakeAmount)) {
                        case (#Ok(p)) {
                            if (val.stakingPower != p) {
                                fixes += 1;
                                val.stakingPower := p;
                            };
                        };
                        case (others) {};
                    };
                };
                case (_) {};
            };
        };
        return #Ok(fixes);
    };

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

    public shared (msg) func stake(emcAmount : Nat, days : Nat, nodeID : Text) : async emcResult {
        switch (nodePool.get(nodeID)) {
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
                switch (stakePool.get(nodeID)) {
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
                                    nodeID = nodeID;
                                    var stakingPower = power;
                                };
                                stakePool.put(nodeID, stakeRecord);
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

    public shared (msg) func unStake(nodeID : Text) : async emcResult {
        switch (stakePool.get(nodeID)) {
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
                            stakePool.delete(nodeID);
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

    public shared query (msg) func myStake(nodeID : Text) : async (Nat, Nat, Nat) {
        switch (stakePool.get(nodeID)) {
            case (?stake) {
                return (stake.stakeAmount, stake.stakeDays, stake.stakingPower);
            };
            case (_) {};
        };
        (0, 0, 10000);
    };

    private func getStakePower(nodeID : Text) : Nat {
        switch (stakePool.get(nodeID)) {
            case (?record) {
                record.stakingPower;
            };
            case (_) {
                switch (getNodeType(nodeID)) {
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
        switch (rewardStatus.get(_nodeID)) {
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
                rewardStatus.put(_nodeID, record);
            };
        };
        totalReward += newReward;
        totalDistributed += newDistribution;
    };

    public shared query (msg) func showNodeRewardStatus(nodeID : Text) : async (Text, Nat, Nat) {
        switch (rewardStatus.get(nodeID)) {
            case (?record) {
                return (nodeID, record.totalReward, record.distributed);
            };
            case (_) {
                return (nodeID, 0, 0);
            };
        };
    };

    public shared query (msg) func showTotalRewardsStatus() : async (Nat, Nat, Nat, Nat) {
        (rewardPoolBalance, totalStaking, totalReward, totalDistributed);
    };

    public shared query (msg) func getNodeStatus() : async (Nat, Nat) {
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

        return (nodePool.size(), pogCount);
    };

    public shared (msg) func postDeposit() : async (Nat) {
        assert (msg.caller == owner);
        let emcBalance = await tokenCanister.balanceOf(Principal.fromActor(self));
        rewardPoolBalance := emcBalance - totalStaking;
        return rewardPoolBalance;
    };

    public shared query (msg) func showFaildReward(start : Nat, limit : Nat) : async [(Text, emcReward.FailedReward)] {
        var recordArray = Iter.toArray(failedRewardPool.entries());

        assert (start <= failedRewardPool.size());
        if (start + limit > failedRewardPool.size()) {
            return Array.subArray<(Text, emcReward.FailedReward)>(recordArray, start, failedRewardPool.size() -start);
        } else {
            return Array.subArray<(Text, emcReward.FailedReward)>(recordArray, start, limit);
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

                            failedRewardPool.put(
                                key,
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
                            );
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
                for (val in rewardRecords.vals()) {
                    totalPower += val.computingPower * getStakePower(val.nodeID);
                };
                for (val in rewardRecords.vals()) {
                    currentRD.put(val.nodeID, dayReward * (val.computingPower * getStakePower(val.nodeID)) / totalPower);
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
    system func preupgrade() {
        nodeEntries := Iter.toArray(nodePool.entries());
        validatorEntries := Iter.toArray(validators.entries());

        rewardStatusEntries := Iter.toArray(rewardStatus.entries());
        failedRewardEntries := Iter.toArray(failedRewardPool.entries());
        stakePoolEntires := Iter.toArray(stakePool.entries());
    };

    system func postupgrade() {
        nodePool := HashMap.fromIter<Text, Node>(nodeEntries.vals(), 1, Text.equal, Text.hash);
        nodeEntries := [];
        validators := HashMap.fromIter<Principal, Time.Time>(validatorEntries.vals(), 1, Principal.equal, Principal.hash);
        validatorEntries := [];

        rewardStatus := HashMap.fromIter<Text, emcReward.RewardStatus>(rewardStatusEntries.vals(), 1, Text.equal, Text.hash);
        failedRewardPool := HashMap.fromIter<Text, emcReward.FailedReward>(failedRewardEntries.vals(), 1, Text.equal, Text.hash);
        stakePool := HashMap.fromIter<Text, emcReward.StakeRecord>(stakePoolEntires.vals(), 1, Text.equal, Text.hash);
    };
};
