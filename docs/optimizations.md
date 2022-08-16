# Optimizations and best practices
Here are some of the best practices we apply to the `autonolas-governance` in order to make the code more gas optimized.
Please note that the following statements concern our code only and do not account for the inherited non-modified code.

- No modifiers;
- No asserts or custom `Panic()` errors;
- Custom `reverts` and no `require` statements;
- Storage vs memory keyword: decision is on what to use after testing for gas spending;
- Explicit type casting even where the compiler does it by default;
- No usage of `safeTransfer()` from the OpenZeppelin (or their analogues) where it is not absolutely necessary;
- Follow `Checks-Effects-Interactions` pattern;
- Events are not subject to reentrancy attacks since events do not cause a function to throw;
- Avoid reverts where the logic allows not to revert and return a zero value instead;
- All `unchecked` statements are commented on;
- All functions with `owner` privileges are not considered to be called from malicious actors and are not meant to be executed for other than common sense scenarios;
- The `OLAS` token does not contain any malicious code, and strictly corresponds to the ERC20 standard;
- Utilize standard code-generated reverts and do not duplicate them, especially in places where the contract itself or any external contracts lead to any negative or false scenario;
- Reverts are utilized where it is absolutely critical and necessary to stop the contract execution such that no state on blockchain has changed;
- Pure storage variables are normally memory-cached to undergo operations, and are assigned back to the storage slot afterwards;
- Prioritize lower consuming gas operations when considering statements (i.e., `(i + 1) > j` instead of `i >= j`);
- Use addresses instead of explicit interface variables;
- Minimize the number of inherited contracts;
- Minimize the nesting level of function calls;
- `enum`-s are used for a better code readability;
- Find tradeoff between optimizations and a code readability;
- When implementing standards (i.e., `ERC20`), the most optimal well-known solutions are utilized;
- When implementing non-standards, the most gas optimized and logical solutions are chosen;
- `true` return value in function returns signals about the function workflow correctness, and does not necessarily mean that state variables are modified during its execution.
