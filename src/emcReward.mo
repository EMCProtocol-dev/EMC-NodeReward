/**
 * Module     : emcReward.mo
 * Copyright  : 2021 EMC Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : EMC Team <dev@emc.app>
 * Stability  : Experimental
 */

import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Float "mo:base/Float";

module {
    let testDayReward : Nat = 5_000_000_000_000;
    let dayRewardBase : Nat = 72072_000_000_000_000_000;
    let testDays : Nat = 60;
    let stageLength : Nat = 90;

    public type RewardRecord = {
        account : Principal;
        var computingPower: Nat;
        var stakingPower: Nat;
        var rewardAmount: Nat;
        var totalPower: Nat;
        var rewardDay : Int;
        var distributed: Time.Time;
    };

    public type RewardStatus = {
        account : Principal;
        var totalReward: Nat;
        var distributed: Nat;
    };

    public type StakeRecord = {
        nodeID : Text;
        nodeWallet : Principal;
        stakeAmount : Nat;
        stakeDays : Nat;
        stakeTime : Time.Time;
        var balance: Nat;
        staker: Principal;
        var stakingPower: Nat;
    };

    private func fiboValue(n:Nat):Nat{
        if(n == 1){
            return 1;
        }else if (n==0){
            return 1;
        }else{
            return fiboValue(n-1) + fiboValue(n-2);
        }
    };

    public func getDayRate(stage:Nat):Float{
        if(stage == 0){
            return 1;
        }else{
            return Float.fromInt(fiboValue(stage-1))/Float.fromInt(fiboValue(stage));
        }
    };

    public func getDayReward(day:Nat): Nat{
        if(day < testDays){
            return testDayReward;
        }else {
            let stage = day - testDays;
            return Int.abs(Float.toInt(getDayRate(stage/90)*Float.fromInt(dayRewardBase)));
        };
    };

    // public func setTestDays(days:Nat){
    //     testDays = days;
    // }
};
