/**
 * Module     : emcNode.mo
 * Copyright  : 2021 EMC Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : EMC Team <dev@emc.app>
 * Stability  : Experimental
 */

import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Int "mo:base/Int";

module {
    // public type NodeType = {
    //     #nodeRouter;
    //     #nodeValidator;
    //     #nodeComputing;
    // };

    public type Node = {
        nodeType : Nat;
        nodeID : Text;
        owner : Principal;
        wallet : Principal;
        registered : Time.Time;
    };

    public type NodeValidationRequest = {
        targetNodeID : Text;
        validator : Principal;
        validationTicket : Nat;
        power: Nat;
    };

    public type NodeValidationUnit = {
        nodeID : Text;
        nodeType : Nat;
        validator : Principal;
        validationTicket : Nat;
        power: Nat;
        validationDay : Int;
    };


};
