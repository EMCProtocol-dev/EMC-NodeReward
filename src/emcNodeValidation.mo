/**
 * Module     : emcNode.mo
 * Copyright  : 2021 EMC Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : EMC Team <dev@emc.app>
 * Stability  : Experimental
 */

import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";

module {
    public type NodeType = {
        #nodeRouter;
        #nodeValidator;
        #nodeComputing;
    };

    public type NodeStatus = {
        #Alive;
        #Dead;
        #Suspended;
    };

    public type Node = {
        nodeType : NodeType;
        nodeID : Text;
        owner : Principal;
        wallet : Principal;
        nodeStatus : NodeStatus;
        registered : Time.Time;
        lastActiveTime: Time.Time;
    };
};
