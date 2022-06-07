## Comparison of the actual solmate token code against the audited v6 release
```
diff --git a/src/tokens/ERC20.sol b/src/tokens/ERC20.sol
index 9d6fe64..110314b 100644
--- a/src/tokens/ERC20.sol
+++ b/src/tokens/ERC20.sol
@@ -6,16 +6,16 @@ pragma solidity >=0.8.0;
 /// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
 /// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
 abstract contract ERC20 {
-    /*///////////////////////////////////////////////////////////////
-                                  EVENTS
+    /*//////////////////////////////////////////////////////////////
+                                 EVENTS
     //////////////////////////////////////////////////////////////*/
 
     event Transfer(address indexed from, address indexed to, uint256 amount);
 
     event Approval(address indexed owner, address indexed spender, uint256 amount);
 
-    /*///////////////////////////////////////////////////////////////
-                             METADATA STORAGE
+    /*//////////////////////////////////////////////////////////////
+                            METADATA STORAGE
     //////////////////////////////////////////////////////////////*/
 
     string public name;
@@ -24,7 +24,7 @@ abstract contract ERC20 {
 
     uint8 public immutable decimals;
 
-    /*///////////////////////////////////////////////////////////////
+    /*//////////////////////////////////////////////////////////////
                               ERC20 STORAGE
     //////////////////////////////////////////////////////////////*/
 
@@ -34,20 +34,17 @@ abstract contract ERC20 {
 
     mapping(address => mapping(address => uint256)) public allowance;
 
-    /*///////////////////////////////////////////////////////////////
-                             EIP-2612 STORAGE
+    /*//////////////////////////////////////////////////////////////
+                            EIP-2612 STORAGE
     //////////////////////////////////////////////////////////////*/
 
-    bytes32 public constant PERMIT_TYPEHASH =
-        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
-
     uint256 internal immutable INITIAL_CHAIN_ID;
 
     bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;
 
     mapping(address => uint256) public nonces;
 
-    /*///////////////////////////////////////////////////////////////
+    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
     //////////////////////////////////////////////////////////////*/
 
@@ -64,8 +61,8 @@ abstract contract ERC20 {
         INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
     }
 
-    /*///////////////////////////////////////////////////////////////
-                              ERC20 LOGIC
+    /*//////////////////////////////////////////////////////////////
+                               ERC20 LOGIC
     //////////////////////////////////////////////////////////////*/
 
     function approve(address spender, uint256 amount) public virtual returns (bool) {
@@ -112,8 +109,8 @@ abstract contract ERC20 {
         return true;
     }
 
-    /*///////////////////////////////////////////////////////////////
-                              EIP-2612 LOGIC
+    /*//////////////////////////////////////////////////////////////
+                             EIP-2612 LOGIC
     //////////////////////////////////////////////////////////////*/
 
     function permit(
@@ -130,16 +127,30 @@ abstract contract ERC20 {
         // Unchecked because the only math done is incrementing
         // the owner's nonce which cannot realistically overflow.
         unchecked {
-            bytes32 digest = keccak256(
-                abi.encodePacked(
-                    "\x19\x01",
-                    DOMAIN_SEPARATOR(),
-                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
-                )
+            address recoveredAddress = ecrecover(
+                keccak256(
+                    abi.encodePacked(
+                        "\x19\x01",
+                        DOMAIN_SEPARATOR(),
+                        keccak256(
+                            abi.encode(
+                                keccak256(
+                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
+                                ),
+                                owner,
+                                spender,
+                                value,
+                                nonces[owner]++,
+                                deadline
+                            )
+                        )
+                    )
+                ),
+                v,
+                r,
+                s
             );
 
-            address recoveredAddress = ecrecover(digest, v, r, s);
-
             require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");
 
             allowance[recoveredAddress][spender] = value;
@@ -165,8 +176,8 @@ abstract contract ERC20 {
             );
     }
 
-    /*///////////////////////////////////////////////////////////////
-                       INTERNAL MINT/BURN LOGIC
+    /*//////////////////////////////////////////////////////////////
+                        INTERNAL MINT/BURN LOGIC
     //////////////////////////////////////////////////////////////*/
 
     function _mint(address to, uint256 amount) internal virtual {

```
