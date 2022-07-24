// 0.5.1-c8a2
// Enable optimization
pragma solidity ^0.5.10;

import "./TRC20.sol";
import "./TRC20Detailed.sol";

/**
 * @title SimpleToken
 * @dev Very simple TRC20 Token example, where all tokens are pre-assigned to the creator.
 * Note they can later distribute these tokens as they wish using `transfer` and other
 * `TRC20` functions.
 */
contract Token is TRC20, TRC20Detailed {


    /**
     * @dev Constructor that gives msg.sender all of existing tokens.
     */
    constructor (string memory name, string memory symbol) public TRC20Detailed(name, symbol, 18) {
        _mint(msg.sender, 10000000000 * (10 ** uint256(decimals())));
    }
}
