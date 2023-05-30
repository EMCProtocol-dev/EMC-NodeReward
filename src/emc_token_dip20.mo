// This is a generated Motoko binding.
// Please use `import service "ic:canister_id"` instead to call canisters on the IC if possible.

module {
  public type Metadata = {
    fee : Nat;
    decimals : Nat8;
    owner : Principal;
    logo : Text;
    name : Text;
    totalSupply : Nat;
    symbol : Text;
  };
  public type Time = Int;
  public type Token = actor {
    allowance : shared query (Principal, Principal) -> async Nat;
    approve : shared (Principal, Nat) -> async TxReceipt;
    balanceOf : shared query Principal -> async Nat;
    burn : shared Nat -> async TxReceipt;
    decimals : shared query () -> async Nat8;
    getAllowanceSize : shared query () -> async Nat;
    getHolders : shared query (Nat, Nat) -> async [(Principal, Nat)];
    getMetadata : shared query () -> async Metadata;
    getTokenFee : shared query () -> async Nat;
    getTokenInfo : shared query () -> async TokenInfo;
    getUserApprovals : shared query Principal -> async [(Principal, Nat)];
    historySize : shared query () -> async Nat;
    logo : shared query () -> async Text;
    mint : shared (Principal, Nat) -> async TxReceipt;
    name : shared query () -> async Text;
    setFee : shared Nat -> ();
    setFeeTo : shared Principal -> ();
    setLogo : shared Text -> ();
    setName : shared Text -> ();
    setOwner : shared Principal -> ();
    symbol : shared query () -> async Text;
    totalSupply : shared query () -> async Nat;
    transfer : shared (Principal, Nat) -> async TxReceipt;
    transferFrom : shared (Principal, Principal, Nat) -> async TxReceipt;
  };
  public type TokenInfo = {
    holderNumber : Nat;
    deployTime : Time;
    metadata : Metadata;
    historySize : Nat;
    cycles : Nat;
    feeTo : Principal;
  };
  public type TxReceipt = {
    #Ok : Nat;
    #Err : {
      #InsufficientAllowance;
      #InsufficientBalance;
      #ErrorOperationStyle;
      #Unauthorized;
      #LedgerTrap;
      #ErrorTo;
      #Other : Text;
      #BlockUsed;
      #AmountTooSmall;
    };
  };
  public type Self = (
    Text,
    Text,
    Text,
    Nat8,
    Nat,
    Principal,
    Nat,
  ) -> async Token
}
