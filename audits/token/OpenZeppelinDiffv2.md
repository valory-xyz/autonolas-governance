## Comparison of the actual OpenZeppelin token code against the audited v2 release
```
diff --git a/contracts/token/ERC20/ERC20.sol b/contracts/token/ERC20/ERC20.sol
index 6de7726d..f782c90b 100644
--- a/contracts/token/ERC20/ERC20.sol
+++ b/contracts/token/ERC20/ERC20.sol
@@ -1,128 +1,196 @@
-pragma solidity ^0.5.0;
+// SPDX-License-Identifier: MIT
+// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/ERC20.sol)
+
+pragma solidity ^0.8.0;
 
 import "./IERC20.sol";
-import "../../math/SafeMath.sol";
+import "./extensions/IERC20Metadata.sol";
+import "../../utils/Context.sol";
 
 /**
- * @dev Implementation of the `IERC20` interface.
+ * @dev Implementation of the {IERC20} interface.
  *
  * This implementation is agnostic to the way tokens are created. This means
- * that a supply mechanism has to be added in a derived contract using `_mint`.
- * For a generic mechanism see `ERC20Mintable`.
+ * that a supply mechanism has to be added in a derived contract using {_mint}.
+ * For a generic mechanism see {ERC20PresetMinterPauser}.
  *
- * *For a detailed writeup see our guide [How to implement supply
- * mechanisms](https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226).*
+ * TIP: For a detailed writeup see our guide
+ * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
+ * to implement supply mechanisms].
  *
- * We have followed general OpenZeppelin guidelines: functions revert instead
- * of returning `false` on failure. This behavior is nonetheless conventional
- * and does not conflict with the expectations of ERC20 applications.
+ * We have followed general OpenZeppelin Contracts guidelines: functions revert
+ * instead returning `false` on failure. This behavior is nonetheless
+ * conventional and does not conflict with the expectations of ERC20
+ * applications.
  *
- * Additionally, an `Approval` event is emitted on calls to `transferFrom`.
+ * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
  * This allows applications to reconstruct the allowance for all accounts just
  * by listening to said events. Other implementations of the EIP may not emit
  * these events, as it isn't required by the specification.
  *
- * Finally, the non-standard `decreaseAllowance` and `increaseAllowance`
+ * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
  * functions have been added to mitigate the well-known issues around setting
- * allowances. See `IERC20.approve`.
+ * allowances. See {IERC20-approve}.
  */
-contract ERC20 is IERC20 {
-    using SafeMath for uint256;
-
-    mapping (address => uint256) private _balances;
+contract ERC20 is Context, IERC20, IERC20Metadata {
+    mapping(address => uint256) private _balances;
 
-    mapping (address => mapping (address => uint256)) private _allowances;
+    mapping(address => mapping(address => uint256)) private _allowances;
 
     uint256 private _totalSupply;
 
+    string private _name;
+    string private _symbol;
+
+    /**
+     * @dev Sets the values for {name} and {symbol}.
+     *
+     * The default value of {decimals} is 18. To select a different value for
+     * {decimals} you should overload it.
+     *
+     * All two of these values are immutable: they can only be set once during
+     * construction.
+     */
+    constructor(string memory name_, string memory symbol_) {
+        _name = name_;
+        _symbol = symbol_;
+    }
+
+    /**
+     * @dev Returns the name of the token.
+     */
+    function name() public view virtual override returns (string memory) {
+        return _name;
+    }
+
+    /**
+     * @dev Returns the symbol of the token, usually a shorter version of the
+     * name.
+     */
+    function symbol() public view virtual override returns (string memory) {
+        return _symbol;
+    }
+
+    /**
+     * @dev Returns the number of decimals used to get its user representation.
+     * For example, if `decimals` equals `2`, a balance of `505` tokens should
+     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
+     *
+     * Tokens usually opt for a value of 18, imitating the relationship between
+     * Ether and Wei. This is the value {ERC20} uses, unless this function is
+     * overridden;
+     *
+     * NOTE: This information is only used for _display_ purposes: it in
+     * no way affects any of the arithmetic of the contract, including
+     * {IERC20-balanceOf} and {IERC20-transfer}.
+     */
+    function decimals() public view virtual override returns (uint8) {
+        return 18;
+    }
+
     /**
-     * @dev See `IERC20.totalSupply`.
+     * @dev See {IERC20-totalSupply}.
      */
-    function totalSupply() public view returns (uint256) {
+    function totalSupply() public view virtual override returns (uint256) {
         return _totalSupply;
     }
 
     /**
-     * @dev See `IERC20.balanceOf`.
+     * @dev See {IERC20-balanceOf}.
      */
-    function balanceOf(address account) public view returns (uint256) {
+    function balanceOf(address account) public view virtual override returns (uint256) {
         return _balances[account];
     }
 
     /**
-     * @dev See `IERC20.transfer`.
+     * @dev See {IERC20-transfer}.
      *
      * Requirements:
      *
-     * - `recipient` cannot be the zero address.
+     * - `to` cannot be the zero address.
      * - the caller must have a balance of at least `amount`.
      */
-    function transfer(address recipient, uint256 amount) public returns (bool) {
-        _transfer(msg.sender, recipient, amount);
+    function transfer(address to, uint256 amount) public virtual override returns (bool) {
+        address owner = _msgSender();
+        _transfer(owner, to, amount);
         return true;
     }
 
     /**
-     * @dev See `IERC20.allowance`.
+     * @dev See {IERC20-allowance}.
      */
-    function allowance(address owner, address spender) public view returns (uint256) {
+    function allowance(address owner, address spender) public view virtual override returns (uint256) {
         return _allowances[owner][spender];
     }
 
     /**
-     * @dev See `IERC20.approve`.
+     * @dev See {IERC20-approve}.
+     *
+     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
+     * `transferFrom`. This is semantically equivalent to an infinite approval.
      *
      * Requirements:
      *
      * - `spender` cannot be the zero address.
      */
-    function approve(address spender, uint256 value) public returns (bool) {
-        _approve(msg.sender, spender, value);
+    function approve(address spender, uint256 amount) public virtual override returns (bool) {
+        address owner = _msgSender();
+        _approve(owner, spender, amount);
         return true;
     }
 
     /**
-     * @dev See `IERC20.transferFrom`.
+     * @dev See {IERC20-transferFrom}.
      *
-     * Emits an `Approval` event indicating the updated allowance. This is not
-     * required by the EIP. See the note at the beginning of `ERC20`;
+     * Emits an {Approval} event indicating the updated allowance. This is not
+     * required by the EIP. See the note at the beginning of {ERC20}.
+     *
+     * NOTE: Does not update the allowance if the current allowance
+     * is the maximum `uint256`.
      *
      * Requirements:
-     * - `sender` and `recipient` cannot be the zero address.
-     * - `sender` must have a balance of at least `value`.
-     * - the caller must have allowance for `sender`'s tokens of at least
+     *
+     * - `from` and `to` cannot be the zero address.
+     * - `from` must have a balance of at least `amount`.
+     * - the caller must have allowance for ``from``'s tokens of at least
      * `amount`.
      */
-    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
-        _transfer(sender, recipient, amount);
-        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount));
+    function transferFrom(
+        address from,
+        address to,
+        uint256 amount
+    ) public virtual override returns (bool) {
+        address spender = _msgSender();
+        _spendAllowance(from, spender, amount);
+        _transfer(from, to, amount);
         return true;
     }
 
     /**
      * @dev Atomically increases the allowance granted to `spender` by the caller.
      *
-     * This is an alternative to `approve` that can be used as a mitigation for
-     * problems described in `IERC20.approve`.
+     * This is an alternative to {approve} that can be used as a mitigation for
+     * problems described in {IERC20-approve}.
      *
-     * Emits an `Approval` event indicating the updated allowance.
+     * Emits an {Approval} event indicating the updated allowance.
      *
      * Requirements:
      *
      * - `spender` cannot be the zero address.
      */
-    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
-        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
+    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
+        address owner = _msgSender();
+        _approve(owner, spender, allowance(owner, spender) + addedValue);
         return true;
     }
 
     /**
      * @dev Atomically decreases the allowance granted to `spender` by the caller.
      *
-     * This is an alternative to `approve` that can be used as a mitigation for
-     * problems described in `IERC20.approve`.
+     * This is an alternative to {approve} that can be used as a mitigation for
+     * problems described in {IERC20-approve}.
      *
-     * Emits an `Approval` event indicating the updated allowance.
+     * Emits an {Approval} event indicating the updated allowance.
      *
      * Requirements:
      *
@@ -130,99 +198,186 @@ contract ERC20 is IERC20 {
      * - `spender` must have allowance for the caller of at least
      * `subtractedValue`.
      */
-    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
-        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue));
+    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
+        address owner = _msgSender();
+        uint256 currentAllowance = allowance(owner, spender);
+        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
+        unchecked {
+            _approve(owner, spender, currentAllowance - subtractedValue);
+        }
+
         return true;
     }
 
     /**
-     * @dev Moves tokens `amount` from `sender` to `recipient`.
+     * @dev Moves `amount` of tokens from `from` to `to`.
      *
-     * This is internal function is equivalent to `transfer`, and can be used to
+     * This internal function is equivalent to {transfer}, and can be used to
      * e.g. implement automatic token fees, slashing mechanisms, etc.
      *
-     * Emits a `Transfer` event.
+     * Emits a {Transfer} event.
      *
      * Requirements:
      *
-     * - `sender` cannot be the zero address.
-     * - `recipient` cannot be the zero address.
-     * - `sender` must have a balance of at least `amount`.
+     * - `from` cannot be the zero address.
+     * - `to` cannot be the zero address.
+     * - `from` must have a balance of at least `amount`.
      */
-    function _transfer(address sender, address recipient, uint256 amount) internal {
-        require(sender != address(0), "ERC20: transfer from the zero address");
-        require(recipient != address(0), "ERC20: transfer to the zero address");
+    function _transfer(
+        address from,
+        address to,
+        uint256 amount
+    ) internal virtual {
+        require(from != address(0), "ERC20: transfer from the zero address");
+        require(to != address(0), "ERC20: transfer to the zero address");
+
+        _beforeTokenTransfer(from, to, amount);
+
+        uint256 fromBalance = _balances[from];
+        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
+        unchecked {
+            _balances[from] = fromBalance - amount;
+        }
+        _balances[to] += amount;
+
+        emit Transfer(from, to, amount);
 
-        _balances[sender] = _balances[sender].sub(amount);
-        _balances[recipient] = _balances[recipient].add(amount);
-        emit Transfer(sender, recipient, amount);
+        _afterTokenTransfer(from, to, amount);
     }
 
     /** @dev Creates `amount` tokens and assigns them to `account`, increasing
      * the total supply.
      *
-     * Emits a `Transfer` event with `from` set to the zero address.
+     * Emits a {Transfer} event with `from` set to the zero address.
      *
-     * Requirements
+     * Requirements:
      *
-     * - `to` cannot be the zero address.
+     * - `account` cannot be the zero address.
      */
-    function _mint(address account, uint256 amount) internal {
+    function _mint(address account, uint256 amount) internal virtual {
         require(account != address(0), "ERC20: mint to the zero address");
 
-        _totalSupply = _totalSupply.add(amount);
-        _balances[account] = _balances[account].add(amount);
+        _beforeTokenTransfer(address(0), account, amount);
+
+        _totalSupply += amount;
+        _balances[account] += amount;
         emit Transfer(address(0), account, amount);
+
+        _afterTokenTransfer(address(0), account, amount);
     }
 
-     /**
+    /**
      * @dev Destroys `amount` tokens from `account`, reducing the
      * total supply.
      *
-     * Emits a `Transfer` event with `to` set to the zero address.
+     * Emits a {Transfer} event with `to` set to the zero address.
      *
-     * Requirements
+     * Requirements:
      *
      * - `account` cannot be the zero address.
      * - `account` must have at least `amount` tokens.
      */
-    function _burn(address account, uint256 value) internal {
+    function _burn(address account, uint256 amount) internal virtual {
         require(account != address(0), "ERC20: burn from the zero address");
 
-        _totalSupply = _totalSupply.sub(value);
-        _balances[account] = _balances[account].sub(value);
-        emit Transfer(account, address(0), value);
+        _beforeTokenTransfer(account, address(0), amount);
+
+        uint256 accountBalance = _balances[account];
+        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
+        unchecked {
+            _balances[account] = accountBalance - amount;
+        }
+        _totalSupply -= amount;
+
+        emit Transfer(account, address(0), amount);
+
+        _afterTokenTransfer(account, address(0), amount);
     }
 
     /**
-     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
+     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
      *
-     * This is internal function is equivalent to `approve`, and can be used to
+     * This internal function is equivalent to `approve`, and can be used to
      * e.g. set automatic allowances for certain subsystems, etc.
      *
-     * Emits an `Approval` event.
+     * Emits an {Approval} event.
      *
      * Requirements:
      *
      * - `owner` cannot be the zero address.
      * - `spender` cannot be the zero address.
      */
-    function _approve(address owner, address spender, uint256 value) internal {
+    function _approve(
+        address owner,
+        address spender,
+        uint256 amount
+    ) internal virtual {
         require(owner != address(0), "ERC20: approve from the zero address");
         require(spender != address(0), "ERC20: approve to the zero address");
 
-        _allowances[owner][spender] = value;
-        emit Approval(owner, spender, value);
+        _allowances[owner][spender] = amount;
+        emit Approval(owner, spender, amount);
     }
 
     /**
-     * @dev Destoys `amount` tokens from `account`.`amount` is then deducted
-     * from the caller's allowance.
+     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
      *
-     * See `_burn` and `_approve`.
+     * Does not update the allowance amount in case of infinite allowance.
+     * Revert if not enough allowance is available.
+     *
+     * Might emit an {Approval} event.
      */
-    function _burnFrom(address account, uint256 amount) internal {
-        _burn(account, amount);
-        _approve(account, msg.sender, _allowances[account][msg.sender].sub(amount));
+    function _spendAllowance(
+        address owner,
+        address spender,
+        uint256 amount
+    ) internal virtual {
+        uint256 currentAllowance = allowance(owner, spender);
+        if (currentAllowance != type(uint256).max) {
+            require(currentAllowance >= amount, "ERC20: insufficient allowance");
+            unchecked {
+                _approve(owner, spender, currentAllowance - amount);
+            }
+        }
     }
+
+    /**
+     * @dev Hook that is called before any transfer of tokens. This includes
+     * minting and burning.
+     *
+     * Calling conditions:
+     *
+     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
+     * will be transferred to `to`.
+     * - when `from` is zero, `amount` tokens will be minted for `to`.
+     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
+     * - `from` and `to` are never both zero.
+     *
+     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
+     */
+    function _beforeTokenTransfer(
+        address from,
+        address to,
+        uint256 amount
+    ) internal virtual {}
+
+    /**
+     * @dev Hook that is called after any transfer of tokens. This includes
+     * minting and burning.
+     *
+     * Calling conditions:
+     *
+     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
+     * has been transferred to `to`.
+     * - when `from` is zero, `amount` tokens have been minted for `to`.
+     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
+     * - `from` and `to` are never both zero.
+     *
+     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
+     */
+    function _afterTokenTransfer(
+        address from,
+        address to,
+        uint256 amount
+    ) internal virtual {}
 }
```
