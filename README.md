# EMC-NodeReward
canister to accept validations of nodes from EMC and distribute corresponding rewards

1. Register & Unregister
  
    func: registerNode: (
  
        nat, // Node Type, 0-router, 1-validator, 2-computing
    
        text, // Node ID, 
    
        principal // wallet principal to receive EMC
  
    )
  
  - Only validators can register validatorNode
  
  - Nodes can share the same wallet
  
2. Submit validations for nodes
  
    func: submitValidation: (
    
        vec record {
        
        validationTicket:nat; //nonce like, to determine specific round of validation.
        
        validator:principal; //validator's operation principal, white listed
        
        power:nat;  //computing power in ms (0.001 seconds)
        
        targetNodeID:text //ID of the being validated node
      
        }  
    )
    

3. Staking to get more reward
  
    3.1 Stake
      
      func: stake: (
        
        nat, //staking amount of EMC
        
        nat, //stakig period
        
        text //ID of the node
      
      )
    
    - Stake 1 time only
    
  3.2 Unstake
    
      func: Unstake: unStake: (
        
        text //ID of the node
      
      ) 
    

4. Automated daily reward distribution.
